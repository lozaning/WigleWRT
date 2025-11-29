package com.wiglewrt.monitor;

import android.Manifest;
import android.animation.ArgbEvaluator;
import android.animation.ObjectAnimator;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.View;
import android.view.animation.AlphaAnimation;
import android.view.animation.Animation;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

public class MainActivity extends Activity {
    private static final String TAG = "WigleWRTMonitor";
    private static final int PERMISSION_REQUEST_CODE = 1;

    // WigleWRT BLE Service UUIDs
    private static final UUID WIGLEWRT_SERVICE_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef0");
    private static final UUID STATUS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef1");
    private static final UUID GPS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef2");
    private static final UUID SESSION_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef4");
    private static final UUID RADIOS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef5");
    private static final UUID ACTIVITY_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef6");

    private static final long SCAN_PERIOD = 15000;
    private static final long REFRESH_INTERVAL = 3000;

    // Colors
    private static final int COLOR_CONNECTED = Color.parseColor("#10B981");
    private static final int COLOR_CONNECTING = Color.parseColor("#F59E0B");
    private static final int COLOR_DISCONNECTED = Color.parseColor("#EF4444");
    private static final int COLOR_TEXT_PRIMARY = Color.parseColor("#F0F6FC");
    private static final int COLOR_TEXT_SECONDARY = Color.parseColor("#8B949E");
    private static final int COLOR_TEXT_MUTED = Color.parseColor("#6E7681");
    private static final int COLOR_SIGNAL_EXCELLENT = Color.parseColor("#10B981");
    private static final int COLOR_SIGNAL_GOOD = Color.parseColor("#22C55E");
    private static final int COLOR_SIGNAL_FAIR = Color.parseColor("#F59E0B");
    private static final int COLOR_SIGNAL_WEAK = Color.parseColor("#EF4444");
    private static final int COLOR_NETWORK_NEW = Color.parseColor("#8B5CF6");

    // UI Elements
    private View statusDot;
    private View liveDot;
    private TextView tvConnectionStatus;
    private Button btnConnect;
    private TextView tvTotalNetworks;
    private TextView tvNewNetworks;
    private TextView tvScannerStatus;
    private TextView tvSessionId;
    private TextView tvDuration;
    private TextView tvGpsStatus;
    private TextView tvLatitude;
    private TextView tvLongitude;
    private TextView tvSatellites;
    private TextView tvFeedCount;
    private LinearLayout emptyState;
    private LinearLayout networkList;

    // BLE
    private BluetoothAdapter bluetoothAdapter;
    private BluetoothLeScanner bleScanner;
    private BluetoothGatt bluetoothGatt;
    private BluetoothGattService wiglewrtService;

    private boolean isScanning = false;
    private boolean isConnected = false;
    private Handler handler = new Handler(Looper.getMainLooper());

    // Data storage
    private int totalNetworks = 0;
    private int newNetworks = 0;
    private String sessionStartTime = null;
    private List<NetworkEntry> recentNetworks = new ArrayList<>();

    // Animations
    private ObjectAnimator pulseAnimator;

    private Runnable refreshRunnable;

    private void initRefreshRunnable() {
        refreshRunnable = new Runnable() {
            @Override
            public void run() {
                if (isConnected) {
                    readAllCharacteristics();
                    handler.postDelayed(refreshRunnable, REFRESH_INTERVAL);
                }
            }
        };
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        initRefreshRunnable();
        initViews();
        initBluetooth();
        setupAnimations();
    }

    private void initViews() {
        statusDot = findViewById(R.id.statusDot);
        liveDot = findViewById(R.id.liveDot);
        tvConnectionStatus = findViewById(R.id.tvConnectionStatus);
        btnConnect = findViewById(R.id.btnConnect);
        tvTotalNetworks = findViewById(R.id.tvTotalNetworks);
        tvNewNetworks = findViewById(R.id.tvNewNetworks);
        tvScannerStatus = findViewById(R.id.tvScannerStatus);
        tvSessionId = findViewById(R.id.tvSessionId);
        tvDuration = findViewById(R.id.tvDuration);
        tvGpsStatus = findViewById(R.id.tvGpsStatus);
        tvLatitude = findViewById(R.id.tvLatitude);
        tvLongitude = findViewById(R.id.tvLongitude);
        tvSatellites = findViewById(R.id.tvSatellites);
        tvFeedCount = findViewById(R.id.tvFeedCount);
        emptyState = findViewById(R.id.emptyState);
        networkList = findViewById(R.id.networkList);

        btnConnect.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (isConnected) {
                    disconnect();
                } else {
                    checkPermissionsAndScan();
                }
            }
        });
    }

    private void setupAnimations() {
        // Pulse animation for live dot when connected
        pulseAnimator = ObjectAnimator.ofFloat(liveDot, "alpha", 1f, 0.3f);
        pulseAnimator.setDuration(1000);
        pulseAnimator.setRepeatMode(ValueAnimator.REVERSE);
        pulseAnimator.setRepeatCount(ValueAnimator.INFINITE);
    }

    private void initBluetooth() {
        BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        if (bluetoothManager != null) {
            bluetoothAdapter = bluetoothManager.getAdapter();
        }

        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
            setConnectionState(ConnectionState.DISCONNECTED);
            Toast.makeText(this, "Please enable Bluetooth", Toast.LENGTH_LONG).show();
            return;
        }

        bleScanner = bluetoothAdapter.getBluetoothLeScanner();
        setConnectionState(ConnectionState.DISCONNECTED);
    }

    private enum ConnectionState {
        DISCONNECTED, SCANNING, CONNECTING, CONNECTED
    }

    private void setConnectionState(ConnectionState state) {
        GradientDrawable dot = new GradientDrawable();
        dot.setShape(GradientDrawable.OVAL);
        dot.setSize(dpToPx(10), dpToPx(10));

        GradientDrawable liveDotDrawable = new GradientDrawable();
        liveDotDrawable.setShape(GradientDrawable.OVAL);
        liveDotDrawable.setSize(dpToPx(8), dpToPx(8));

        switch (state) {
            case DISCONNECTED:
                dot.setColor(COLOR_DISCONNECTED);
                liveDotDrawable.setColor(COLOR_DISCONNECTED);
                tvConnectionStatus.setText("Disconnected");
                tvConnectionStatus.setTextColor(COLOR_TEXT_SECONDARY);
                btnConnect.setText("Connect to Router");
                btnConnect.setEnabled(true);
                if (pulseAnimator.isRunning()) pulseAnimator.cancel();
                liveDot.setAlpha(1f);
                break;

            case SCANNING:
                dot.setColor(COLOR_CONNECTING);
                liveDotDrawable.setColor(COLOR_CONNECTING);
                tvConnectionStatus.setText("Scanning...");
                tvConnectionStatus.setTextColor(COLOR_CONNECTING);
                btnConnect.setText("Scanning...");
                btnConnect.setEnabled(false);
                break;

            case CONNECTING:
                dot.setColor(COLOR_CONNECTING);
                liveDotDrawable.setColor(COLOR_CONNECTING);
                tvConnectionStatus.setText("Connecting...");
                tvConnectionStatus.setTextColor(COLOR_CONNECTING);
                btnConnect.setText("Connecting...");
                btnConnect.setEnabled(false);
                break;

            case CONNECTED:
                dot.setColor(COLOR_CONNECTED);
                liveDotDrawable.setColor(COLOR_CONNECTED);
                tvConnectionStatus.setText("Connected");
                tvConnectionStatus.setTextColor(COLOR_CONNECTED);
                btnConnect.setText("Disconnect");
                btnConnect.setEnabled(true);
                if (!pulseAnimator.isRunning()) pulseAnimator.start();
                break;
        }

        statusDot.setBackground(dot);
        liveDot.setBackground(liveDotDrawable);
    }

    private void checkPermissionsAndScan() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION}, PERMISSION_REQUEST_CODE);
            return;
        }
        startScan();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            boolean allGranted = true;
            for (int result : grantResults) {
                if (result != PackageManager.PERMISSION_GRANTED) {
                    allGranted = false;
                    break;
                }
            }
            if (allGranted) {
                startScan();
            } else {
                Toast.makeText(this, "Bluetooth permissions required", Toast.LENGTH_SHORT).show();
            }
        }
    }

    private void startScan() {
        if (bleScanner == null || isScanning) return;

        setConnectionState(ConnectionState.SCANNING);

        ScanFilter filter = new ScanFilter.Builder()
                .setServiceUuid(new ParcelUuid(WIGLEWRT_SERVICE_UUID))
                .build();

        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();

        try {
            bleScanner.startScan(Arrays.asList(filter), settings, scanCallback);
            isScanning = true;
            handler.postDelayed(new Runnable() {
                @Override
                public void run() {
                    stopScan();
                }
            }, SCAN_PERIOD);
        } catch (SecurityException e) {
            setConnectionState(ConnectionState.DISCONNECTED);
            Toast.makeText(this, "Scan permission denied", Toast.LENGTH_SHORT).show();
        }
    }

    private void stopScan() {
        if (!isScanning) return;
        try {
            bleScanner.stopScan(scanCallback);
        } catch (SecurityException e) {
            Log.e(TAG, "Stop scan permission denied", e);
        }
        isScanning = false;
        if (!isConnected) {
            setConnectionState(ConnectionState.DISCONNECTED);
            Toast.makeText(this, "WigleWRT device not found", Toast.LENGTH_SHORT).show();
        }
    }

    private final ScanCallback scanCallback = new MyScanCallback();

    private class MyScanCallback extends ScanCallback {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            BluetoothDevice device = result.getDevice();
            Log.d(TAG, "Found device: " + device.getAddress());
            stopScan();
            connectToDevice(device);
        }

        @Override
        public void onScanFailed(int errorCode) {
            Log.e(TAG, "Scan failed: " + errorCode);
            stopScan();
            setConnectionState(ConnectionState.DISCONNECTED);
        }
    }

    private void connectToDevice(BluetoothDevice device) {
        setConnectionState(ConnectionState.CONNECTING);
        try {
            bluetoothGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
        } catch (SecurityException e) {
            setConnectionState(ConnectionState.DISCONNECTED);
            Toast.makeText(this, "Connection permission denied", Toast.LENGTH_SHORT).show();
        }
    }

    private void disconnect() {
        handler.removeCallbacks(refreshRunnable);
        if (bluetoothGatt != null) {
            try {
                bluetoothGatt.disconnect();
                bluetoothGatt.close();
            } catch (SecurityException e) {
                Log.e(TAG, "Disconnect permission denied", e);
            }
            bluetoothGatt = null;
        }
        isConnected = false;
        wiglewrtService = null;
        setConnectionState(ConnectionState.DISCONNECTED);
        resetUI();
    }

    private void resetUI() {
        tvTotalNetworks.setText("0");
        tvNewNetworks.setText("0");
        tvScannerStatus.setText("Idle");
        tvScannerStatus.setTextColor(COLOR_TEXT_MUTED);
        tvSessionId.setText("--");
        tvDuration.setText("--:--");
        tvGpsStatus.setText("No Fix");
        tvGpsStatus.setTextColor(COLOR_DISCONNECTED);
        tvLatitude.setText("--");
        tvLongitude.setText("--");
        tvSatellites.setText("--");
        tvFeedCount.setText("0 networks");
        emptyState.setVisibility(View.VISIBLE);
        networkList.setVisibility(View.GONE);
        networkList.removeAllViews();
        recentNetworks.clear();
    }

    private final BluetoothGattCallback gattCallback = new MyGattCallback();

    private class MyGattCallback extends BluetoothGattCallback {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                try {
                    gatt.discoverServices();
                } catch (SecurityException e) {
                    Log.e(TAG, "Service discovery permission denied", e);
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        isConnected = false;
                        setConnectionState(ConnectionState.DISCONNECTED);
                    }
                });
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                wiglewrtService = gatt.getService(WIGLEWRT_SERVICE_UUID);
                if (wiglewrtService != null) {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            isConnected = true;
                            setConnectionState(ConnectionState.CONNECTED);
                            readAllCharacteristics();
                            handler.postDelayed(refreshRunnable, REFRESH_INTERVAL);
                        }
                    });
                } else {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            Toast.makeText(MainActivity.this, "WigleWRT service not found", Toast.LENGTH_SHORT).show();
                            disconnect();
                        }
                    });
                }
            }
        }

        @Override
        public void onCharacteristicRead(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                byte[] data = characteristic.getValue();
                if (data != null) {
                    final String json = new String(data, StandardCharsets.UTF_8);
                    final UUID uuid = characteristic.getUuid();
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            processCharacteristicData(uuid, json);
                        }
                    });
                }
            }
        }
    }

    private void readAllCharacteristics() {
        if (wiglewrtService == null || bluetoothGatt == null) return;

        List<UUID> charUuids = Arrays.asList(
                STATUS_CHAR_UUID,
                GPS_CHAR_UUID,
                SESSION_CHAR_UUID,
                ACTIVITY_CHAR_UUID
        );

        readNextCharacteristic(charUuids, 0);
    }

    private void readNextCharacteristic(final List<UUID> uuids, final int index) {
        if (index >= uuids.size() || wiglewrtService == null || bluetoothGatt == null) {
            return;
        }

        BluetoothGattCharacteristic characteristic = wiglewrtService.getCharacteristic(uuids.get(index));
        if (characteristic != null) {
            try {
                bluetoothGatt.readCharacteristic(characteristic);
            } catch (SecurityException e) {
                Log.e(TAG, "Read characteristic permission denied", e);
            }
        }

        final int nextIndex = index + 1;
        handler.postDelayed(new Runnable() {
            @Override
            public void run() {
                readNextCharacteristic(uuids, nextIndex);
            }
        }, 250);
    }

    private void processCharacteristicData(UUID uuid, String json) {
        try {
            JSONObject data = new JSONObject(json);

            if (uuid.equals(STATUS_CHAR_UUID)) {
                processStatusData(data);
            } else if (uuid.equals(GPS_CHAR_UUID)) {
                processGpsData(data);
            } else if (uuid.equals(SESSION_CHAR_UUID)) {
                processSessionData(data);
            } else if (uuid.equals(ACTIVITY_CHAR_UUID)) {
                processActivityData(data);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error parsing: " + json, e);
        }
    }

    private void processStatusData(JSONObject data) {
        boolean running = data.optBoolean("running", false);
        totalNetworks = data.optInt("total_networks", 0);
        newNetworks = data.optInt("session_new", 0);

        tvTotalNetworks.setText(String.valueOf(totalNetworks));
        tvNewNetworks.setText(String.valueOf(newNetworks));

        if (running) {
            tvScannerStatus.setText("Running");
            tvScannerStatus.setTextColor(COLOR_CONNECTED);
        } else {
            tvScannerStatus.setText("Stopped");
            tvScannerStatus.setTextColor(COLOR_DISCONNECTED);
        }
    }

    private void processGpsData(JSONObject data) {
        boolean available = data.optBoolean("available", false);
        boolean fix = data.optBoolean("fix", false) || data.optInt("fix", 0) == 1;
        int sats = data.optInt("sats", 0);
        String lat = data.optString("lat", "");
        String lon = data.optString("lon", "");

        tvSatellites.setText(String.valueOf(sats));

        if (!available) {
            tvGpsStatus.setText("No GPS");
            tvGpsStatus.setTextColor(COLOR_DISCONNECTED);
            tvLatitude.setText("--");
            tvLongitude.setText("--");
        } else if (!fix) {
            tvGpsStatus.setText("Searching");
            tvGpsStatus.setTextColor(COLOR_CONNECTING);
            tvLatitude.setText("--");
            tvLongitude.setText("--");
        } else {
            tvGpsStatus.setText("Fix");
            tvGpsStatus.setTextColor(COLOR_CONNECTED);
            if (!lat.isEmpty()) {
                try {
                    double latVal = Double.parseDouble(lat);
                    tvLatitude.setText(String.format("%.5f", latVal));
                } catch (NumberFormatException e) {
                    tvLatitude.setText(lat);
                }
            }
            if (!lon.isEmpty()) {
                try {
                    double lonVal = Double.parseDouble(lon);
                    tvLongitude.setText(String.format("%.5f", lonVal));
                } catch (NumberFormatException e) {
                    tvLongitude.setText(lon);
                }
            }
        }
    }

    private void processSessionData(JSONObject data) {
        String sessionId = data.optString("session_id", "--");
        String startTime = data.optString("start_time", "");

        // Shorten session ID for display
        if (sessionId.length() > 8) {
            sessionId = sessionId.substring(0, 8) + "...";
        }
        tvSessionId.setText(sessionId);

        // Calculate duration if we have start time
        if (!startTime.isEmpty()) {
            sessionStartTime = startTime;
            updateDuration();
        }
    }

    private void updateDuration() {
        if (sessionStartTime == null) return;
        // Simple duration display
        tvDuration.setText("Active");
    }

    private void processActivityData(JSONObject data) {
        if (!data.has("entries")) return;

        try {
            JSONArray entries = data.getJSONArray("entries");
            recentNetworks.clear();

            for (int i = 0; i < entries.length() && i < 10; i++) {
                JSONObject entry = entries.getJSONObject(i);
                NetworkEntry network = new NetworkEntry();
                network.isNew = entry.optBoolean("is_new", false);
                network.ssid = entry.optString("ssid", "<hidden>");
                network.bssid = entry.optString("bssid", "");
                network.channel = entry.optString("channel", "");
                network.signal = entry.optInt("signal", -100);
                network.encryption = entry.optString("encryption", "");
                recentNetworks.add(network);
            }

            updateNetworkList();
        } catch (Exception e) {
            Log.e(TAG, "Error parsing activity", e);
        }
    }

    private void updateNetworkList() {
        tvFeedCount.setText(recentNetworks.size() + " networks");

        if (recentNetworks.isEmpty()) {
            emptyState.setVisibility(View.VISIBLE);
            networkList.setVisibility(View.GONE);
            return;
        }

        emptyState.setVisibility(View.GONE);
        networkList.setVisibility(View.VISIBLE);
        networkList.removeAllViews();

        LayoutInflater inflater = LayoutInflater.from(this);

        for (NetworkEntry network : recentNetworks) {
            View itemView = inflater.inflate(R.layout.item_network, networkList, false);

            TextView tvSsid = itemView.findViewById(R.id.tvSsid);
            TextView tvBssid = itemView.findViewById(R.id.tvBssid);
            TextView tvChannel = itemView.findViewById(R.id.tvChannel);
            TextView tvSignal = itemView.findViewById(R.id.tvSignal);
            TextView tvEncryption = itemView.findViewById(R.id.tvEncryption);
            TextView tvNewBadge = itemView.findViewById(R.id.tvNewBadge);
            TextView tvSignalIcon = itemView.findViewById(R.id.tvSignalIcon);

            tvSsid.setText(network.ssid.isEmpty() ? "<hidden>" : network.ssid);
            tvBssid.setText(network.bssid);
            tvChannel.setText("Ch " + network.channel);
            tvSignal.setText(network.signal + " dBm");

            // Signal color
            int signalColor;
            if (network.signal >= -50) {
                signalColor = COLOR_SIGNAL_EXCELLENT;
                tvSignalIcon.setText("📶");
            } else if (network.signal >= -60) {
                signalColor = COLOR_SIGNAL_GOOD;
                tvSignalIcon.setText("📶");
            } else if (network.signal >= -70) {
                signalColor = COLOR_SIGNAL_FAIR;
                tvSignalIcon.setText("📶");
            } else {
                signalColor = COLOR_SIGNAL_WEAK;
                tvSignalIcon.setText("📶");
            }
            tvSignal.setTextColor(signalColor);

            // Encryption color
            String enc = network.encryption.toUpperCase();
            tvEncryption.setText(enc.isEmpty() ? "OPEN" : enc);
            if (enc.contains("WPA3")) {
                tvEncryption.setTextColor(Color.parseColor("#10B981"));
            } else if (enc.contains("WPA2")) {
                tvEncryption.setTextColor(Color.parseColor("#22C55E"));
            } else if (enc.contains("WPA")) {
                tvEncryption.setTextColor(Color.parseColor("#F59E0B"));
            } else if (enc.contains("WEP")) {
                tvEncryption.setTextColor(Color.parseColor("#EF4444"));
            } else {
                tvEncryption.setTextColor(Color.parseColor("#DC2626"));
            }

            // New badge
            if (network.isNew) {
                tvNewBadge.setVisibility(View.VISIBLE);
                itemView.setBackgroundResource(R.drawable.network_item_new);
            } else {
                tvNewBadge.setVisibility(View.GONE);
                itemView.setBackgroundResource(R.drawable.network_item);
            }

            networkList.addView(itemView);
        }
    }

    private int dpToPx(int dp) {
        return (int) (dp * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (pulseAnimator != null) {
            pulseAnimator.cancel();
        }
        disconnect();
    }

    // Helper class for network entries
    private static class NetworkEntry {
        boolean isNew;
        String ssid;
        String bssid;
        String channel;
        int signal;
        String encryption;
    }
}
