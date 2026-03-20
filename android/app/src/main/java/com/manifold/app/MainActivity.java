package com.manifold.app;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;

public class MainActivity extends Activity {
    private static final String TAG = "Manifold";
    
    static {
        try {
            Log.i(TAG, "Loading native library...");
            System.loadLibrary("ManifoldMobile");
            Log.i(TAG, "Native library loaded successfully");
        } catch (Exception e) {
            Log.e(TAG, "Failed to load native library: " + e.getMessage());
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.i(TAG, "MainActivity.onCreate called");
        // Native code handles the UI
    }
    
    @Override
    protected void onResume() {
        super.onResume();
        Log.i(TAG, "MainActivity.onResume called");
    }
}
