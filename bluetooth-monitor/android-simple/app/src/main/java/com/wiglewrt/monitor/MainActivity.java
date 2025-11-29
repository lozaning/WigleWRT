package com.wiglewrt.monitor;

import android.Manifest;
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
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
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
    private static final long REFRESH_INTERVAL = 5000;

    private TextView tvStatus;
    private TextView tvData;
    private Button btnConnect;
    private ScrollView scrollView;

    private BluetoothAdapter bluetoothAdapter;
    private BluetoothLeScanner bleScanner;
    private BluetoothGatt bluetoothGatt;
    private BluetoothGattService wiglewrtService;

    private boolean isScanning = false;
    private boolean isConnected = false;
    private Handler handler = new Handler(Looper.getMainLooper());
    private StringBuilder dataBuilder = new StringBuilder();

    private final Runnable refreshRunnable = new Runnable() {
        @Override
        public void run() {
            if (isConnected) {
                readAllCharacteristics();
                handler.postDelayed(this, REFRESH_INTERVAL);
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        tvStatus = findViewById(R.id.tvStatus);
        tvData = findViewById(R.id.tvData);
        btnConnect = findViewById(R.id.btnConnect);
        scrollView = findViewById(R.id.scrollView);

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

        initBluetooth();
    }

    private void initBluetooth() {
        BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        if (bluetoothManager != null) {
            bluetoothAdapter = bluetoothManager.getAdapter();
        }

        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
            updateStatus("Please enable Bluetooth");
            return;
        }

        bleScanner = bluetoothAdapter.getBluetoothLeScanner();
        updateStatus("Ready to connect");
    }

    private void checkPermissionsAndScan() {
        // For API 30 and below, only need location permission for BLE scanning
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
                Toast.makeText(this, "Permissions required", Toast.LENGTH_SHORT).show();
            }
        }
    }

    private void startScan() {
        if (bleScanner == null || isScanning) return;

        updateStatus("Scanning for WigleWRT...");
        btnConnect.setEnabled(false);

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
            updateStatus("Scan permission denied");
            btnConnect.setEnabled(true);
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
        btnConnect.setEnabled(true);
        if (!isConnected) {
            updateStatus("Device not found. Tap to retry.");
        }
    }

    private final ScanCallback scanCallback = new ScanCallback() {
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
            updateStatus("Scan failed. Tap to retry.");
        }
    };

    private void connectToDevice(BluetoothDevice device) {
        updateStatus("Connecting...");
        try {
            bluetoothGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
        } catch (SecurityException e) {
            updateStatus("Connection permission denied");
            btnConnect.setEnabled(true);
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
        updateStatus("Disconnected");
        btnConnect.setText("Connect");
        dataBuilder = new StringBuilder();
        tvData.setText("");
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
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
                        updateStatus("Disconnected");
                        btnConnect.setText("Connect");
                        btnConnect.setEnabled(true);
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
                            updateStatus("Connected to WigleWRT");
                            btnConnect.setText("Disconnect");
                            btnConnect.setEnabled(true);
                            readAllCharacteristics();
                            handler.postDelayed(refreshRunnable, REFRESH_INTERVAL);
                        }
                    });
                } else {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            updateStatus("WigleWRT service not found");
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
    };

    private void readAllCharacteristics() {
        if (wiglewrtService == null || bluetoothGatt == null) return;

        dataBuilder = new StringBuilder();
        dataBuilder.append("=== WigleWRT Status ===\n\n");

        List<UUID> charUuids = Arrays.asList(
                STATUS_CHAR_UUID,
                GPS_CHAR_UUID,
                SESSION_CHAR_UUID,
                RADIOS_CHAR_UUID,
                ACTIVITY_CHAR_UUID
        );

        readNextCharacteristic(charUuids, 0);
    }

    private void readNextCharacteristic(final List<UUID> uuids, final int index) {
        if (index >= uuids.size() || wiglewrtService == null || bluetoothGatt == null) {
            // All done, update display
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    tvData.setText(dataBuilder.toString());
                    scrollView.fullScroll(View.FOCUS_UP);
                }
            });
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

        handler.postDelayed(new Runnable() {
            @Override
            public void run() {
                readNextCharacteristic(uuids, index + 1);
            }
        }, 300);
    }

    private void processCharacteristicData(UUID uuid, String json) {
        try {
            JSONObject data = new JSONObject(json);

            if (uuid.equals(STATUS_CHAR_UUID)) {
                boolean running = data.optBoolean("running", false);
                int total = data.optInt("total_networks", 0);
                int sessionNew = data.optInt("session_new", 0);

                dataBuilder.append("--- Scanner Status ---\n");
                dataBuilder.append("Status: ").append(running ? "RUNNING" : "STOPPED").append("\n");
                dataBuilder.append("Total Networks: ").append(total).append("\n");
                dataBuilder.append("New This Session: ").append(sessionNew).append("\n\n");

            } else if (uuid.equals(GPS_CHAR_UUID)) {
                boolean available = data.optBoolean("available", false);
                boolean fix = data.optBoolean("fix", false) || data.optInt("fix", 0) == 1;
                int sats = data.optInt("sats", 0);
                String lat = data.optString("lat", "");
                String lon = data.optString("lon", "");

                dataBuilder.append("--- GPS Status ---\n");
                if (!available) {
                    dataBuilder.append("GPS: Not available\n");
                } else if (!fix) {
                    dataBuilder.append("GPS: Searching (").append(sats).append(" sats)\n");
                } else {
                    dataBuilder.append("GPS: Fix (").append(sats).append(" sats)\n");
                    dataBuilder.append("Lat: ").append(lat).append("\n");
                    dataBuilder.append("Lon: ").append(lon).append("\n");
                }
                dataBuilder.append("\n");

            } else if (uuid.equals(SESSION_CHAR_UUID)) {
                String sessionId = data.optString("session_id", "-");
                String startTime = data.optString("start_time", "-");
                int newNetworks = data.optInt("new_networks", 0);

                dataBuilder.append("--- Current Session ---\n");
                dataBuilder.append("Session ID: ").append(sessionId).append("\n");
                dataBuilder.append("Started: ").append(startTime).append("\n");
                dataBuilder.append("New Networks: ").append(newNetworks).append("\n\n");

            } else if (uuid.equals(RADIOS_CHAR_UUID)) {
                dataBuilder.append("--- Radio Config ---\n");
                if (data.has("radios")) {
                    JSONArray radios = data.getJSONArray("radios");
                    for (int i = 0; i < radios.length(); i++) {
                        JSONObject radio = radios.getJSONObject(i);
                        String id = radio.optString("id", "radio" + i);
                        boolean enabled = radio.optBoolean("enabled", false);
                        String band = radio.optString("band", "unknown");
                        String channels = radio.optString("channels", "");

                        dataBuilder.append(id).append(" (").append(band).append("): ");
                        dataBuilder.append(enabled ? "Active" : "Disabled");
                        dataBuilder.append("\n  Channels: ").append(channels).append("\n");
                    }
                }
                if (data.has("hop_interval")) {
                    dataBuilder.append("Hop Interval: ").append(data.getString("hop_interval")).append("ms\n");
                }
                dataBuilder.append("\n");

            } else if (uuid.equals(ACTIVITY_CHAR_UUID)) {
                dataBuilder.append("--- Recent Activity ---\n");
                if (data.has("entries")) {
                    JSONArray entries = data.getJSONArray("entries");
                    if (entries.length() == 0) {
                        dataBuilder.append("No recent activity\n");
                    } else {
                        for (int i = 0; i < entries.length(); i++) {
                            JSONObject entry = entries.getJSONObject(i);
                            boolean isNew = entry.optBoolean("is_new", false);
                            String ssid = entry.optString("ssid", "<hidden>");
                            String bssid = entry.optString("bssid", "");
                            String channel = entry.optString("channel", "");
                            String signal = entry.optString("signal", "");
                            String time = entry.optString("timestamp", "");

                            dataBuilder.append(isNew ? "[NEW] " : "      ");
                            dataBuilder.append(ssid).append("\n");
                            dataBuilder.append("      ").append(bssid).append("\n");
                            dataBuilder.append("      Ch:").append(channel);
                            dataBuilder.append(" Sig:").append(signal).append("dBm");
                            dataBuilder.append(" @").append(time).append("\n\n");
                        }
                    }
                }
            }

            tvData.setText(dataBuilder.toString());

        } catch (Exception e) {
            Log.e(TAG, "Error parsing: " + json, e);
        }
    }

    private void updateStatus(String status) {
        tvStatus.setText(status);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        disconnect();
    }
}
