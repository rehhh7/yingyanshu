package com.yys.kit;

import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothServerSocket;
import android.bluetooth.BluetoothSocket;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.util.Log;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 英眼书安卓工具插件：系统分享面板 + 蓝牙互传（RFCOMM）
 * 与 LanSync（局域网）同一套交互协议：
 *   请求方连上后先发 "REQ|<设备名>\n"；
 *   对方同意后回 4 字节大端长度 + UTF-8 JSON；长度 0 = 拒绝。
 */
public class YysKit extends GodotPlugin {
	private static final String TAG = "YysKit";
	private static final UUID APP_UUID = UUID.fromString("3f6b2a10-7c4e-4b2d-9a1f-2e5c8d0b9a77");
	private static final int MAX_BYTES = 64 * 1024 * 1024;

	private final ExecutorService io = Executors.newCachedThreadPool();
	private BluetoothAdapter adapter;
	private BluetoothServerSocket serverSocket;
	private BluetoothSocket activeSocket;
	private BroadcastReceiver discoveryReceiver;
	private volatile String pendingJson = "";   // 宿主方待发送的备份内容

	public YysKit(Godot godot) {
		super(godot);
		adapter = BluetoothAdapter.getDefaultAdapter();
	}

	@Override
	public String getPluginName() {
		return "YysKit";
	}

	@Override
	public Set<SignalInfo> getPluginSignals() {
		Set<SignalInfo> s = new HashSet<>();
		s.add(new SignalInfo("bt_device_found", String.class, String.class));   // 名称, MAC
		s.add(new SignalInfo("bt_incoming_request", String.class));             // 对方设备名
		s.add(new SignalInfo("bt_received", String.class));                     // 收到的 JSON
		s.add(new SignalInfo("bt_done", Boolean.class, String.class));          // 成功?, 消息
		return s;
	}

	private Activity act() {
		return getGodot().getActivity();
	}

	// ===================== URI 读字节（系统文件选择器返回的 content:// 兜底） =====================

	/**
	 * 读取系统文件选择器返回的 URI（content:// / file://）或真实路径为字节数组；失败返回 null。
	 * 部分机型上 Godot FileAccess 读不动 content://（godot#105328 / 提案#14263），
	 * 走 ContentResolver.openInputStream 百分百可读（选择器已授予该 URI 的读权限）。
	 */
	@UsedByGodot
	public byte[] read_uri_bytes(String uriStr) {
		Activity a = act();
		if (a == null) return null;
		try {
			java.io.InputStream in;
			if (uriStr.startsWith("content://") || uriStr.startsWith("file://")) {
				in = a.getContentResolver().openInputStream(Uri.parse(uriStr));
			} else {
				in = new FileInputStream(new File(uriStr));
			}
			if (in == null) return null;
			java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
			byte[] buf = new byte[64 * 1024];
			int n;
			long total = 0;
			while ((n = in.read(buf)) > 0) {
				out.write(buf, 0, n);
				total += n;
				if (total > MAX_BYTES) {
					in.close();
					return null;
				}
			}
			in.close();
			return out.toByteArray();
		} catch (Exception e) {
			Log.e(TAG, "read_uri_bytes failed: " + uriStr, e);
			return null;
		}
	}

	// ===================== 系统分享面板 =====================

	@UsedByGodot
	public void share_text(String text, String title) {
		Activity a = act();
		if (a == null) return;
		Intent send = new Intent(Intent.ACTION_SEND);
		send.setType("text/plain");
		send.putExtra(Intent.EXTRA_TEXT, text);
		a.startActivity(Intent.createChooser(send, title));
	}

	@UsedByGodot
	public void share_file(String absPath, String mime, String title) {
		Activity a = act();
		if (a == null) return;
		try {
			File src = new File(absPath);
			File dir = new File(a.getFilesDir(), "share_cache");
			//noinspection ResultOfMethodCallIgnored
			dir.mkdirs();
			File dst = new File(dir, src.getName());
			copyFile(src, dst);
			Uri uri = new Uri.Builder().scheme("content")
					.authority(a.getPackageName() + ".yys_share")
					.encodedPath("/" + dst.getName()).build();
			Intent send = new Intent(Intent.ACTION_SEND);
			send.setType(mime);
			send.putExtra(Intent.EXTRA_STREAM, uri);
			send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			a.startActivity(Intent.createChooser(send, title));
		} catch (Exception e) {
			Log.e(TAG, "share_file failed", e);
		}
	}

	private static void copyFile(File src, File dst) throws Exception {
		FileInputStream in = new FileInputStream(src);
		FileOutputStream out = new FileOutputStream(dst);
		byte[] buf = new byte[64 * 1024];
		int n;
		while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
		out.flush();
		out.close();
		in.close();
	}

	// ===================== 蓝牙互传 =====================

	/** 0=不支持蓝牙 1=已关闭 2=已开启 */
	@UsedByGodot
	public int bt_state() {
		if (adapter == null) return 0;
		return adapter.isEnabled() ? 2 : 1;
	}

	/** 弹出系统「打开蓝牙」对话框 */
	@UsedByGodot
	public void bt_enable() {
		Activity a = act();
		if (a == null || adapter == null) return;
		try {
			a.startActivity(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE));
		} catch (Exception e) {
			Log.e(TAG, "bt_enable failed", e);
		}
	}

	/** 申请蓝牙相关运行时权限；已具备返回 true */
	@UsedByGodot
	public boolean bt_ensure_perms() {
		Activity a = act();
		if (a == null) return false;
		if (Build.VERSION.SDK_INT >= 31) {
			if (a.checkSelfPermission("android.permission.BLUETOOTH_CONNECT") == PackageManager.PERMISSION_GRANTED
					&& a.checkSelfPermission("android.permission.BLUETOOTH_SCAN") == PackageManager.PERMISSION_GRANTED) {
				return true;
			}
			a.requestPermissions(new String[]{"android.permission.BLUETOOTH_CONNECT", "android.permission.BLUETOOTH_SCAN"}, 7717);
			return false;
		} else {
			if (a.checkSelfPermission("android.permission.ACCESS_FINE_LOCATION") == PackageManager.PERMISSION_GRANTED) {
				return true;
			}
			a.requestPermissions(new String[]{"android.permission.ACCESS_FINE_LOCATION"}, 7717);
			return false;
		}
	}

	/** 宿主方：开始可被连接（RFCOMM 监听），jsonPayload 为被接受后要发的备份 */
	@UsedByGodot
	public void bt_host_start(String jsonPayload) {
		bt_stop();
		pendingJson = jsonPayload;
		io.execute(() -> {
			try {
				serverSocket = adapter.listenUsingRfcommWithServiceRecord("YingYanShu", APP_UUID);
				BluetoothSocket sock = serverSocket.accept(60 * 1000);
				activeSocket = sock;
				handleIncoming(sock);
			} catch (Exception e) {
				Log.e(TAG, "host accept failed", e);
				emitSignal("bt_done", false, "等待连接超时或被取消");
			}
		});
	}

	/** 搜索方：列出已配对设备 + 开始发现周围设备（结果走 bt_device_found 信号） */
	@UsedByGodot
	public void bt_discover() {
		Activity a = act();
		if (a == null || adapter == null) return;
		try {
			for (BluetoothDevice d : adapter.getBondedDevices()) {
				emitSignal("bt_device_found", safeName(d), d.getAddress());
			}
		} catch (SecurityException ignored) {
		}
		if (discoveryReceiver != null) {
			try { a.unregisterReceiver(discoveryReceiver); } catch (Exception ignored) {}
		}
		discoveryReceiver = new BroadcastReceiver() {
			@Override
			public void onReceive(Context ctx, Intent intent) {
				if (BluetoothDevice.ACTION_FOUND.equals(intent.getAction())) {
					BluetoothDevice d = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
					if (d != null) {
						try {
							emitSignal("bt_device_found", safeName(d), d.getAddress());
						} catch (SecurityException ignored) {
						}
					}
				}
			}
		};
		a.registerReceiver(discoveryReceiver, new IntentFilter(BluetoothDevice.ACTION_FOUND));
		try {
			adapter.startDiscovery();
		} catch (SecurityException ignored) {
		}
	}

	private String safeName(BluetoothDevice d) {
		try {
			String n = d.getName();
			return n == null ? "未知设备" : n;
		} catch (SecurityException e) {
			return "未知设备";
		}
	}

	/** 请求方：连接指定设备并发出互传请求（myName 会显示在对方确认框里） */
	@UsedByGodot
	public void bt_connect(String mac, String myName) {
		io.execute(() -> {
			try {
				adapter.cancelDiscovery();
				BluetoothSocket sock = adapter.getRemoteDevice(mac).createRfcommSocketToServiceRecord(APP_UUID);
				sock.connect();
				activeSocket = sock;
				DataOutputStream out = new DataOutputStream(sock.getOutputStream());
				out.write(("REQ|" + myName + "\n").getBytes(StandardCharsets.UTF_8));
				out.flush();
				DataInputStream in = new DataInputStream(sock.getInputStream());
				int len = in.readInt();
				if (len <= 0) {
					emitSignal("bt_done", false, "对方拒绝了互传");
					closeQuietly(sock);
					return;
				}
				if (len > MAX_BYTES) {
					emitSignal("bt_done", false, "数据长度异常");
					closeQuietly(sock);
					return;
				}
				byte[] buf = new byte[len];
				in.readFully(buf);
				emitSignal("bt_received", new String(buf, StandardCharsets.UTF_8));
				closeQuietly(sock);
			} catch (Exception e) {
				Log.e(TAG, "bt_connect failed", e);
				emitSignal("bt_done", false, "连接失败（对方开了互传页面吗？蓝牙开着吗？）");
			}
		});
	}

	private void handleIncoming(BluetoothSocket sock) {
		io.execute(() -> {
			try {
				DataInputStream in = new DataInputStream(sock.getInputStream());
				StringBuilder sb = new StringBuilder();
				int ch;
				while ((ch = in.read()) != -1 && ch != '\n' && sb.length() < 4096) {
					sb.append((char) ch);
				}
				String req = sb.toString();
				if (req.startsWith("REQ|")) {
					emitSignal("bt_incoming_request", req.substring(4));
					// 等待 GDScript 调 bt_respond
				} else {
					closeQuietly(sock);
				}
			} catch (Exception e) {
				Log.e(TAG, "handleIncoming failed", e);
				emitSignal("bt_done", false, "连接中断");
			}
		});
	}

	/** 宿主方：回应对方的互传请求；接受则随后发送备份数据 */
	@UsedByGodot
	public void bt_respond(boolean accept) {
		BluetoothSocket sock = activeSocket;
		if (sock == null) return;
		io.execute(() -> {
			try {
				DataOutputStream out = new DataOutputStream(sock.getOutputStream());
				if (!accept) {
					out.writeInt(0);
					out.flush();
					closeQuietly(sock);
					return;
				}
				byte[] data = pendingJson.getBytes(StandardCharsets.UTF_8);
				out.writeInt(data.length);
				out.write(data);
				out.flush();
				emitSignal("bt_done", true, "已发送");
				Thread.sleep(500);   // 给内核缓冲一点时间再关
				closeQuietly(sock);
			} catch (Exception e) {
				Log.e(TAG, "bt_respond failed", e);
				emitSignal("bt_done", false, "发送中断");
			}
		});
	}

	@UsedByGodot
	public void bt_stop() {
		try { if (serverSocket != null) serverSocket.close(); } catch (Exception ignored) {}
		serverSocket = null;
		closeQuietly(activeSocket);
		activeSocket = null;
		Activity a = act();
		if (a != null && discoveryReceiver != null) {
			try { a.unregisterReceiver(discoveryReceiver); } catch (Exception ignored) {}
			discoveryReceiver = null;
		}
	}

	private static void closeQuietly(BluetoothSocket s) {
		if (s != null) {
			try { s.close(); } catch (Exception ignored) {}
		}
	}
}
