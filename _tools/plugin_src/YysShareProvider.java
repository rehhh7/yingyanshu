package com.yys.kit;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

/**
 * 零依赖的只读文件 Provider：把 filesDir/share_cache 里的文件以 content:// URI 提供给分享面板
 * （复用系统分享需要 content URI，自写 Provider 避免引入 androidx 依赖）
 */
public class YysShareProvider extends ContentProvider {
	@Override
	public boolean onCreate() {
		return true;
	}

	@Override
	public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
		String name = uri.getLastPathSegment();
		if (name == null || name.contains("..") || name.contains("/")) {
			throw new FileNotFoundException("bad name");
		}
		File f = new File(getContext().getFilesDir(), "share_cache/" + name);
		if (!f.exists()) {
			throw new FileNotFoundException(name);
		}
		return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY);
	}

	@Override
	public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
		String name = uri.getLastPathSegment();
		File f = new File(getContext().getFilesDir(), "share_cache/" + name);
		MatrixCursor c = new MatrixCursor(new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE});
		c.addRow(new Object[]{name, f.exists() ? f.length() : 0});
		return c;
	}

	@Override
	public String getType(Uri uri) {
		return "application/octet-stream";
	}

	@Override
	public Uri insert(Uri uri, ContentValues values) {
		return null;
	}

	@Override
	public int delete(Uri uri, String selection, String[] selectionArgs) {
		return 0;
	}

	@Override
	public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
		return 0;
	}
}
