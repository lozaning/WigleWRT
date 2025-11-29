package com.wiglewrt.monitor;

import android.Manifest;
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
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.cardview.widget.CardView;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

public class MainActivity extends AppCompatActivity {
    private static final String TAG = "WigleWRTMonitor";

    // WigleWRT BLE Service UUIDs
    private static final UUID WIGLEWRT_SERVICE_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef0");
    private static final UUID STATUS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef1");
    private static final UUID GPS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef2");
    private static final UUID NETWORKS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef3");
    private static final UUID SESSION_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef4");
    private static final UUID RADIOS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef5");
    private static final UUID ACTIVITY_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef6");

    private static final long SCAN_PERIOD = 15000; // 15 seconds
    private static final long REFRESH_INTERVAL = 5000; // 5 seconds

    // UI Elements
    private TextView tvConnectionStatus;
    private TextView tvScannerStatus;
    private TextView tvGpsStatus;
    private TextView tvSessionId;
    private TextView tvTotalNetworks;
    private TextView tvSessionStart;
    private TextView tvNewNetworks;
    private LinearLayout layoutRadios;
    private RecyclerView rvActivity;
    private Button btnConnect;
    private Button btnRefresh;
    private ProgressBar progressBar;
    private SwipeRefreshLayout swipeRefresh;
    private CardView cardStatus;
    private CardView cardGps;
    private CardView cardSession;
    private CardView cardRadios;
    private CardView cardActivity;

    // BLE
    private BluetoothAdapter bluetoothAdapter;
    private BluetoothLeScanner bleScanner;
    private BluetoothGatt bluetoothGatt;
    private boolean isScanning = false;
    private boolean isConnected = false;
    private BluetoothGattService wiglewrtService;

    private Handler handler;
    private Gson gson;
    private ActivityAdapter activityAdapter;

    private final Handler refreshHandler = new Handler(Looper.getMainLooper());
    private final Runnable refreshRunnable = new Runnable() {
        @Override
        public void run() {
            if (isConnected) {
                readAllCharacteristics();
                refreshHandler.postDelayed(this, REFRESH_INTERVAL);
            }
        }
    };

    private final ActivityResultLauncher<String[]> permissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestMultiplePermissions(), result -> {
                boolean allGranted = true;
                for (Boolean granted : result.values()) {
                    if (!granted) {
                        allGranted = false;
                        break;
                    }
                }
                if (allGranted) {
                    initBluetooth();
                } else {
                    Toast.makeText(this, "Bluetooth permissions required", Toast.LENGTH_LONG).show();
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        handler = new Handler(Looper.getMainLooper());
        gson = new Gson();

        initViews();
        checkPermissions();
    }

    private void initViews() {
        tvConnectionStatus = findViewById(R.id.tvConnectionStatus);
        tvScannerStatus = findViewById(R.id.tvScannerStatus);
        tvGpsStatus = findViewById(R.id.tvGpsStatus);
        tvSessionId = findViewById(R.id.tvSessionId);
        tvTotalNetworks = findViewById(R.id.tvTotalNetworks);
        tvSessionStart = findViewById(R.id.tvSessionStart);
        tvNewNetworks = findViewById(R.id.tvNewNetworks);
        layoutRadios = findViewById(R.id.layoutRadios);
        rvActivity = findViewById(R.id.rvActivity);
        btnConnect = findViewById(R.id.btnConnect);
        btnRefresh = findViewById(R.id.btnRefresh);
        progressBar = findViewById(R.id.progressBar);
        swipeRefresh = findViewById(R.id.swipeRefresh);
        cardStatus = findViewById(R.id.cardStatus);
        cardGps = findViewById(R.id.cardGps);
        cardSession = findViewById(R.id.cardSession);
        cardRadios = findViewById(R.id.cardRadios);
        cardActivity = findViewById(R.id.cardActivity);

        // Setup RecyclerView
        activityAdapter = new ActivityAdapter();
        rvActivity.setLayoutManager(new LinearLayoutManager(this));
        rvActivity.setAdapter(activityAdapter);

        // Button listeners
        btnConnect.setOnClickListener(v -> {
            if (isConnected) {
                disconnect();
            } else {
                startScan();
            }
        });

        btnRefresh.setOnClickListener(v -> {
            if (isConnected) {
                readAllCharacteristics();
            }
        });

        swipeRefresh.setOnRefreshListener(() -> {
            if (isConnected) {
                readAllCharacteristics();
            }
            swipeRefresh.setRefreshing(false);
        });

        // Initially hide data cards
        setCardsVisible(false);
    }

    private void setCardsVisible(boolean visible) {
        int visibility = visible ? View.VISIBLE : View.GONE;
        cardStatus.setVisibility(visibility);
        cardGps.setVisibility(visibility);
        cardSession.setVisibility(visibility);
        cardRadios.setVisibility(visibility);
        cardActivity.setVisibility(visibility);
        btnRefresh.setVisibility(visibility);
    }

    private void checkPermissions() {
        List<String> permissions = new ArrayList<>();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN)
                    != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.BLUETOOTH_SCAN);
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)
                    != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.BLUETOOTH_CONNECT);
            }
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION);
        }

        if (!permissions.isEmpty()) {
            permissionLauncher.launch(permissions.toArray(new String[0]));
        } else {
            initBluetooth();
        }
    }

    private void initBluetooth() {
        BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        if (bluetoothManager != null) {
            bluetoothAdapter = bluetoothManager.getAdapter();
        }

        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
            Toast.makeText(this, "Please enable Bluetooth", Toast.LENGTH_LONG).show();
            return;
        }

        bleScanner = bluetoothAdapter.getBluetoothLeScanner();
        updateConnectionStatus("Ready to connect");
    }

    private void startScan() {
        if (bleScanner == null) {
            Toast.makeText(this, "BLE Scanner not available", Toast.LENGTH_SHORT).show();
            return;
        }

        if (isScanning) {
            return;
        }

        progressBar.setVisibility(View.VISIBLE);
        updateConnectionStatus("Scanning for WigleWRT...");
        btnConnect.setEnabled(false);

        // Scan filter for WigleWRT service
        ScanFilter filter = new ScanFilter.Builder()
                .setServiceUuid(new ParcelUuid(WIGLEWRT_SERVICE_UUID))
                .build();

        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();

        try {
            bleScanner.startScan(Arrays.asList(filter), settings, scanCallback);
            isScanning = true;

            // Stop scan after timeout
            handler.postDelayed(this::stopScan, SCAN_PERIOD);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for BLE scan", e);
            Toast.makeText(this, "Bluetooth permission denied", Toast.LENGTH_SHORT).show();
        }
    }

    private void stopScan() {
        if (!isScanning) return;

        try {
            bleScanner.stopScan(scanCallback);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for stopping scan", e);
        }
        isScanning = false;
        progressBar.setVisibility(View.GONE);
        btnConnect.setEnabled(true);

        if (!isConnected) {
            updateConnectionStatus("Device not found. Tap to retry.");
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
            updateConnectionStatus("Scan failed. Tap to retry.");
        }
    };

    private void connectToDevice(BluetoothDevice device) {
        updateConnectionStatus("Connecting...");
        progressBar.setVisibility(View.VISIBLE);

        try {
            bluetoothGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission denied for GATT connection", e);
            Toast.makeText(this, "Bluetooth permission denied", Toast.LENGTH_SHORT).show();
        }
    }

    private void disconnect() {
        refreshHandler.removeCallbacks(refreshRunnable);

        if (bluetoothGatt != null) {
            try {
                bluetoothGatt.disconnect();
                bluetoothGatt.close();
            } catch (SecurityException e) {
                Log.e(TAG, "Permission denied for disconnect", e);
            }
            bluetoothGatt = null;
        }

        isConnected = false;
        wiglewrtService = null;
        updateConnectionStatus("Disconnected");
        btnConnect.setText("Connect");
        setCardsVisible(false);
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "Connected to GATT server");
                try {
                    gatt.discoverServices();
                } catch (SecurityException e) {
                    Log.e(TAG, "Permission denied for service discovery", e);
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "Disconnected from GATT server");
                runOnUiThread(() -> {
                    isConnected = false;
                    progressBar.setVisibility(View.GONE);
                    updateConnectionStatus("Disconnected");
                    btnConnect.setText("Connect");
                    btnConnect.setEnabled(true);
                    setCardsVisible(false);
                });
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                wiglewrtService = gatt.getService(WIGLEWRT_SERVICE_UUID);
                if (wiglewrtService != null) {
                    runOnUiThread(() -> {
                        isConnected = true;
                        progressBar.setVisibility(View.GONE);
                        updateConnectionStatus("Connected to WigleWRT");
                        btnConnect.setText("Disconnect");
                        btnConnect.setEnabled(true);
                        setCardsVisible(true);

                        // Start reading characteristics
                        readAllCharacteristics();

                        // Start periodic refresh
                        refreshHandler.postDelayed(refreshRunnable, REFRESH_INTERVAL);
                    });
                } else {
                    Log.e(TAG, "WigleWRT service not found");
                    runOnUiThread(() -> {
                        updateConnectionStatus("Service not found");
                        disconnect();
                    });
                }
            }
        }

        @Override
        public void onCharacteristicRead(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                byte[] data = characteristic.getValue();
                if (data != null) {
                    String json = new String(data, StandardCharsets.UTF_8);
                    UUID uuid = characteristic.getUuid();

                    runOnUiThread(() -> processCharacteristicData(uuid, json));
                }
            }
        }
    };

    private void readAllCharacteristics() {
        if (wiglewrtService == null || bluetoothGatt == null) return;

        // Queue reads for all characteristics
        List<UUID> charUuids = Arrays.asList(
                STATUS_CHAR_UUID,
                GPS_CHAR_UUID,
                SESSION_CHAR_UUID,
                RADIOS_CHAR_UUID,
                ACTIVITY_CHAR_UUID
        );

        readNextCharacteristic(charUuids, 0);
    }

    private void readNextCharacteristic(List<UUID> uuids, int index) {
        if (index >= uuids.size() || wiglewrtService == null || bluetoothGatt == null) return;

        BluetoothGattCharacteristic characteristic = wiglewrtService.getCharacteristic(uuids.get(index));
        if (characteristic != null) {
            try {
                bluetoothGatt.readCharacteristic(characteristic);
            } catch (SecurityException e) {
                Log.e(TAG, "Permission denied for reading characteristic", e);
            }
        }

        // Schedule next read
        handler.postDelayed(() -> readNextCharacteristic(uuids, index + 1), 200);
    }

    private void processCharacteristicData(UUID uuid, String json) {
        try {
            JsonObject data = gson.fromJson(json, JsonObject.class);

            if (uuid.equals(STATUS_CHAR_UUID)) {
                updateScannerStatus(data);
            } else if (uuid.equals(GPS_CHAR_UUID)) {
                updateGpsStatus(data);
            } else if (uuid.equals(SESSION_CHAR_UUID)) {
                updateSessionInfo(data);
            } else if (uuid.equals(RADIOS_CHAR_UUID)) {
                updateRadioConfig(data);
            } else if (uuid.equals(ACTIVITY_CHAR_UUID)) {
                updateActivity(data);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error parsing characteristic data: " + json, e);
        }
    }

    private void updateScannerStatus(JsonObject data) {
        boolean running = data.has("running") && data.get("running").getAsBoolean();
        int totalNetworks = data.has("total_networks") ? data.get("total_networks").getAsInt() : 0;
        int sessionNew = data.has("session_new") ? data.get("session_new").getAsInt() : 0;

        tvScannerStatus.setText(running ? "Running" : "Stopped");
        tvScannerStatus.setTextColor(getColor(running ? R.color.status_running : R.color.status_stopped));
        tvTotalNetworks.setText(String.valueOf(totalNetworks));
        tvNewNetworks.setText(String.valueOf(sessionNew));
    }

    private void updateGpsStatus(JsonObject data) {
        boolean available = data.has("available") && data.get("available").getAsBoolean();
        boolean fix = data.has("fix") && (data.get("fix").getAsBoolean() || data.get("fix").getAsInt() == 1);
        int sats = data.has("sats") ? data.get("sats").getAsInt() : 0;
        String lat = data.has("lat") ? data.get("lat").getAsString() : "";
        String lon = data.has("lon") ? data.get("lon").getAsString() : "";

        String gpsText;
        int color;

        if (!available) {
            gpsText = "No GPS device";
            color = R.color.status_error;
        } else if (!fix) {
            gpsText = "Searching (" + sats + " sats)";
            color = R.color.status_warning;
        } else {
            gpsText = "Fix (" + sats + " sats): " + formatCoord(lat) + ", " + formatCoord(lon);
            color = R.color.status_running;
        }

        tvGpsStatus.setText(gpsText);
        tvGpsStatus.setTextColor(getColor(color));
    }

    private String formatCoord(String coord) {
        if (coord == null || coord.isEmpty()) return "-";
        try {
            double d = Double.parseDouble(coord);
            return String.format("%.5f", d);
        } catch (NumberFormatException e) {
            return coord;
        }
    }

    private void updateSessionInfo(JsonObject data) {
        String sessionId = data.has("session_id") ? data.get("session_id").getAsString() : "-";
        String startTime = data.has("start_time") ? data.get("start_time").getAsString() : "-";
        int newNetworks = data.has("new_networks") ? data.get("new_networks").getAsInt() : 0;

        tvSessionId.setText(sessionId.isEmpty() ? "-" : sessionId);
        tvSessionStart.setText(startTime.isEmpty() ? "-" : startTime);
        tvNewNetworks.setText(String.valueOf(newNetworks));
    }

    private void updateRadioConfig(JsonObject data) {
        layoutRadios.removeAllViews();

        if (data.has("radios")) {
            JsonArray radios = data.getAsJsonArray("radios");
            for (int i = 0; i < radios.size(); i++) {
                JsonObject radio = radios.get(i).getAsJsonObject();
                String id = radio.has("id") ? radio.get("id").getAsString() : "radio" + i;
                boolean enabled = radio.has("enabled") && radio.get("enabled").getAsBoolean();
                String band = radio.has("band") ? radio.get("band").getAsString() : "unknown";
                String channels = radio.has("channels") ? radio.get("channels").getAsString() : "";

                TextView tv = new TextView(this);
                String bandLabel = band.equals("2g") ? "2.4GHz" : band.equals("5g") ? "5GHz" : "Dual";
                String status = enabled ? "Active" : "Disabled";
                tv.setText(String.format("phy%d (%s): %s - Ch: %s", i, bandLabel, status, channels));
                tv.setTextColor(getColor(enabled ? R.color.text_primary : R.color.text_secondary));
                tv.setPadding(0, 4, 0, 4);
                layoutRadios.addView(tv);
            }
        }

        if (data.has("hop_interval")) {
            TextView tv = new TextView(this);
            tv.setText("Hop interval: " + data.get("hop_interval").getAsString() + "ms");
            tv.setTextColor(getColor(R.color.text_secondary));
            tv.setPadding(0, 8, 0, 0);
            layoutRadios.addView(tv);
        }
    }

    private void updateActivity(JsonObject data) {
        List<NetworkEntry> entries = new ArrayList<>();

        if (data.has("entries")) {
            JsonArray arr = data.getAsJsonArray("entries");
            for (int i = 0; i < arr.size(); i++) {
                JsonObject entry = arr.get(i).getAsJsonObject();
                NetworkEntry ne = new NetworkEntry();
                ne.timestamp = entry.has("timestamp") ? entry.get("timestamp").getAsString() : "";
                ne.bssid = entry.has("bssid") ? entry.get("bssid").getAsString() : "";
                ne.ssid = entry.has("ssid") ? entry.get("ssid").getAsString() : "<hidden>";
                ne.channel = entry.has("channel") ? entry.get("channel").getAsString() : "";
                ne.signal = entry.has("signal") ? entry.get("signal").getAsString() : "";
                ne.isNew = entry.has("is_new") && entry.get("is_new").getAsBoolean();
                entries.add(ne);
            }
        }

        activityAdapter.setEntries(entries);
    }

    private void updateConnectionStatus(String status) {
        tvConnectionStatus.setText(status);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        disconnect();
    }

    // Inner class for network entries
    public static class NetworkEntry {
        public String timestamp;
        public String bssid;
        public String ssid;
        public String channel;
        public String signal;
        public boolean isNew;
    }
}
