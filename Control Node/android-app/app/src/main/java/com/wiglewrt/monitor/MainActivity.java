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
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;
import android.util.Log;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedList;
import java.util.List;
import java.util.Queue;
import java.util.UUID;

public class MainActivity extends AppCompatActivity {
    private static final String TAG = "WigleWRT";
    private static final int PERMISSION_REQUEST_CODE = 1;
    private static final long SCAN_TIMEOUT = 10000; // 10 seconds
    private static final long POLL_INTERVAL = 2000; // 2 seconds

    // BLE UUIDs - must match router's BLE server
    private static final UUID SERVICE_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef0");
    private static final UUID STATUS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef1");
    private static final UUID GPS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef2");
    private static final UUID NETWORKS_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef3");
    private static final UUID ACTIVITY_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef6");
    private static final UUID CONTROL_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef7");
    private static final UUID CONFIG_CHAR_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef8");

    private static final int MAX_NETWORKS_DISPLAYED = 25;

    private BluetoothAdapter bluetoothAdapter;
    private BluetoothLeScanner bleScanner;
    private BluetoothGatt bluetoothGatt;
    private BluetoothGattService wigleService;

    private Handler handler = new Handler(Looper.getMainLooper());
    private boolean isScanning = false;
    private boolean isConnected = false;

    // BLE operation queue - serializes reads/writes since BLE can only handle one at a time
    private Queue<BleOperation> operationQueue = new LinkedList<>();
    private boolean isOperationPending = false;

    // Simple class to hold BLE operations
    private static class BleOperation {
        enum Type { READ, WRITE }
        Type type;
        UUID charUuid;
        byte[] writeData;

        static BleOperation read(UUID uuid) {
            BleOperation op = new BleOperation();
            op.type = Type.READ;
            op.charUuid = uuid;
            return op;
        }

        static BleOperation write(UUID uuid, byte[] data) {
            BleOperation op = new BleOperation();
            op.type = Type.WRITE;
            op.charUuid = uuid;
            op.writeData = data;
            return op;
        }
    }

    // UI elements
    private TextView connectionStatus;
    private Button connectButton;
    private Button startScanButton;
    private Button stopScanButton;
    private TextView scannerStatus;
    private View scannerIndicator;
    private TextView uniqueNetworks;
    private TextView totalSightings;
    private TextView gpsStatus;
    private View gpsIndicator;
    private TextView gpsCoords;
    private RecyclerView networksRecycler;
    private NetworkAdapter networkAdapter;
    private List<NetworkItem> networkList = new ArrayList<>();
    private BluetoothGattCharacteristic controlCharacteristic;
    private BluetoothGattCharacteristic configCharacteristic;

    // Config UI elements
    private Spinner channelModeSpinner;
    private Spinner channelOffsetSpinner;
    private Button saveConfigButton;
    private String currentChannelMode = "common";
    private String currentChannelOffset = "1";
    private int currentHopInterval = 500;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        initViews();
        initBluetooth();
        requestPermissions();
    }

    private void initViews() {
        connectionStatus = findViewById(R.id.connectionStatus);
        connectButton = findViewById(R.id.connectButton);
        startScanButton = findViewById(R.id.startScanButton);
        stopScanButton = findViewById(R.id.stopScanButton);
        scannerStatus = findViewById(R.id.scannerStatus);
        scannerIndicator = findViewById(R.id.scannerIndicator);
        uniqueNetworks = findViewById(R.id.uniqueNetworks);
        totalSightings = findViewById(R.id.totalSightings);
        gpsStatus = findViewById(R.id.gpsStatus);
        gpsIndicator = findViewById(R.id.gpsIndicator);
        gpsCoords = findViewById(R.id.gpsCoords);
        networksRecycler = findViewById(R.id.networksRecycler);

        networkAdapter = new NetworkAdapter(networkList);
        networksRecycler.setLayoutManager(new LinearLayoutManager(this));
        networksRecycler.setAdapter(networkAdapter);

        // Config UI
        channelModeSpinner = findViewById(R.id.channelModeSpinner);
        channelOffsetSpinner = findViewById(R.id.channelOffsetSpinner);
        saveConfigButton = findViewById(R.id.saveConfigButton);

        // Setup Channel Mode spinner
        String[] channelModes = {"Common", "All"};
        ArrayAdapter<String> modeAdapter = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_item, channelModes);
        modeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        channelModeSpinner.setAdapter(modeAdapter);

        // Setup Channel Offset spinner
        String[] channelOffsets = {"Disabled", "Enabled"};
        ArrayAdapter<String> offsetAdapter = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_item, channelOffsets);
        offsetAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        channelOffsetSpinner.setAdapter(offsetAdapter);

        // Save config button
        saveConfigButton.setOnClickListener(v -> saveConfig());

        connectButton.setOnClickListener(v -> {
            if (isConnected) {
                disconnect();
            } else {
                startScan();
            }
        });

        // Scanner control buttons
        startScanButton.setOnClickListener(v -> startRouterScan(500));
        stopScanButton.setOnClickListener(v -> stopRouterScan());

        // Initially disable scan control buttons until connected
        updateScanControlButtons(false);
    }

    private void initBluetooth() {
        BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        if (bluetoothManager != null) {
            bluetoothAdapter = bluetoothManager.getAdapter();
            if (bluetoothAdapter != null) {
                bleScanner = bluetoothAdapter.getBluetoothLeScanner();
            }
        }

        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
            Toast.makeText(this, "Bluetooth is not enabled", Toast.LENGTH_LONG).show();
        }
    }

    private void requestPermissions() {
        List<String> permissions = new ArrayList<>();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_SCAN);
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT);
        }
        permissions.add(Manifest.permission.ACCESS_FINE_LOCATION);
        permissions.add(Manifest.permission.ACCESS_COARSE_LOCATION);

        List<String> needed = new ArrayList<>();
        for (String perm : permissions) {
            if (ContextCompat.checkSelfPermission(this, perm) != PackageManager.PERMISSION_GRANTED) {
                needed.add(perm);
            }
        }

        if (!needed.isEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toArray(new String[0]), PERMISSION_REQUEST_CODE);
        }
    }

    private void startScan() {
        if (bleScanner == null) {
            Toast.makeText(this, "BLE Scanner not available", Toast.LENGTH_SHORT).show();
            return;
        }

        if (isScanning) return;
        isScanning = true;

        updateConnectionStatus("Scanning...", R.color.gps_no_fix);
        connectButton.setEnabled(false);

        ScanFilter filter = new ScanFilter.Builder()
                .setServiceUuid(new ParcelUuid(SERVICE_UUID))
                .build();

        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();

        try {
            bleScanner.startScan(Collections.singletonList(filter), settings, scanCallback);

            // Stop scan after timeout
            handler.postDelayed(() -> {
                if (isScanning) {
                    stopScan();
                    Toast.makeText(MainActivity.this, "Device not found", Toast.LENGTH_SHORT).show();
                    updateConnectionStatus("Disconnected", R.color.status_stopped);
                    connectButton.setEnabled(true);
                }
            }, SCAN_TIMEOUT);
        } catch (SecurityException e) {
            Log.e(TAG, "BLE scan permission denied", e);
            Toast.makeText(this, "BLE permission denied", Toast.LENGTH_SHORT).show();
        }
    }

    private void stopScan() {
        if (bleScanner != null && isScanning) {
            try {
                bleScanner.stopScan(scanCallback);
            } catch (SecurityException e) {
                Log.e(TAG, "BLE stop scan permission denied", e);
            }
            isScanning = false;
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
            isScanning = false;
            runOnUiThread(() -> {
                updateConnectionStatus("Scan failed", R.color.status_stopped);
                connectButton.setEnabled(true);
            });
        }
    };

    private void connectToDevice(BluetoothDevice device) {
        runOnUiThread(() -> updateConnectionStatus("Connecting...", R.color.gps_no_fix));

        try {
            bluetoothGatt = device.connectGatt(this, false, gattCallback);
        } catch (SecurityException e) {
            Log.e(TAG, "Connect permission denied", e);
        }
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "Connected to GATT server");
                try {
                    gatt.discoverServices();
                } catch (SecurityException e) {
                    Log.e(TAG, "Discover services permission denied", e);
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "Disconnected from GATT server");
                isConnected = false;
                runOnUiThread(() -> {
                    updateConnectionStatus("Disconnected", R.color.status_stopped);
                    connectButton.setText("Scan for Device");
                    connectButton.setEnabled(true);
                });
                stopPolling();
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                wigleService = gatt.getService(SERVICE_UUID);
                if (wigleService != null) {
                    isConnected = true;
                    // Get the control and config characteristics
                    controlCharacteristic = wigleService.getCharacteristic(CONTROL_CHAR_UUID);
                    configCharacteristic = wigleService.getCharacteristic(CONFIG_CHAR_UUID);
                    runOnUiThread(() -> {
                        updateConnectionStatus("Connected", R.color.status_running);
                        connectButton.setText("Disconnect");
                        connectButton.setEnabled(true);
                        updateScanControlButtons(true);
                    });
                    // Request larger MTU for JSON payloads (default 23 bytes is too small)
                    try {
                        gatt.requestMtu(512);
                    } catch (SecurityException e) {
                        Log.e(TAG, "MTU request permission denied", e);
                        // Start polling anyway with smaller MTU
                        startPolling();
                    }
                } else {
                    Log.e(TAG, "WigleWRT service not found");
                }
            }
        }

        @Override
        public void onMtuChanged(BluetoothGatt gatt, int mtu, int status) {
            Log.d(TAG, "MTU changed to: " + mtu + " status: " + status);
            // Start polling after MTU negotiation completes
            startPolling();
        }

        @Override
        public void onCharacteristicRead(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
            // Clear the pending flag so we can process the next operation
            isOperationPending = false;

            if (status == BluetoothGatt.GATT_SUCCESS) {
                String value = characteristic.getStringValue(0);
                UUID uuid = characteristic.getUuid();

                Log.d(TAG, "Read " + uuid + ": " + value);

                runOnUiThread(() -> processCharacteristicData(uuid, value));
            }

            // Process next queued operation
            processNextOperation();
        }

        @Override
        public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
            // Clear the pending flag so we can process the next operation
            isOperationPending = false;

            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "Write successful: " + characteristic.getUuid());
            } else {
                Log.e(TAG, "Write failed: " + characteristic.getUuid() + " status=" + status);
            }

            // Process next queued operation
            processNextOperation();
        }
    };

    private void startPolling() {
        handler.post(pollRunnable);
    }

    private void stopPolling() {
        handler.removeCallbacks(pollRunnable);
    }

    private final Runnable pollRunnable = new Runnable() {
        @Override
        public void run() {
            if (isConnected && wigleService != null) {
                // Queue all reads - they will be processed sequentially
                queueRead(STATUS_CHAR_UUID);
                queueRead(GPS_CHAR_UUID);
                queueRead(ACTIVITY_CHAR_UUID);
                queueRead(CONFIG_CHAR_UUID);
            }

            if (isConnected) {
                handler.postDelayed(this, POLL_INTERVAL);
            }
        }
    };

    // Queue a read operation
    private void queueRead(UUID charUuid) {
        operationQueue.add(BleOperation.read(charUuid));
        processNextOperation();
    }

    // Queue a write operation
    private void queueWrite(UUID charUuid, byte[] data) {
        operationQueue.add(BleOperation.write(charUuid, data));
        processNextOperation();
    }

    // Process the next operation in the queue
    private synchronized void processNextOperation() {
        if (isOperationPending || operationQueue.isEmpty()) return;
        if (bluetoothGatt == null || wigleService == null) return;

        BleOperation op = operationQueue.poll();
        BluetoothGattCharacteristic characteristic = wigleService.getCharacteristic(op.charUuid);
        if (characteristic == null) {
            processNextOperation(); // Characteristic not found, try next
            return;
        }

        try {
            isOperationPending = true;
            if (op.type == BleOperation.Type.READ) {
                bluetoothGatt.readCharacteristic(characteristic);
            } else {
                characteristic.setValue(op.writeData);
                bluetoothGatt.writeCharacteristic(characteristic);
            }
        } catch (SecurityException e) {
            Log.e(TAG, "BLE operation permission denied", e);
            isOperationPending = false;
            processNextOperation(); // Try next
        }
    }

    private void processCharacteristicData(UUID uuid, String data) {
        try {
            JSONObject json = new JSONObject(data);

            if (uuid.equals(STATUS_CHAR_UUID)) {
                boolean running = json.optBoolean("running", false);
                int unique = json.optInt("unique_networks", 0);
                int sightings = json.optInt("total_sightings", 0);

                scannerStatus.setText(running ? "Running" : "Stopped");
                setIndicatorColor(scannerIndicator, running ? R.color.status_running : R.color.status_stopped);
                uniqueNetworks.setText("Unique Networks: " + unique);
                totalSightings.setText("Total Sightings: " + sightings);

            } else if (uuid.equals(GPS_CHAR_UUID)) {
                boolean fix = json.optBoolean("fix", false);
                int sats = json.optInt("sats", 0);
                double lat = json.optDouble("lat", 0);
                double lon = json.optDouble("lon", 0);

                gpsStatus.setText(fix ? "Fix (" + sats + " sats)" : "No Fix (" + sats + " sats)");
                setIndicatorColor(gpsIndicator, fix ? R.color.gps_fix : R.color.gps_no_fix);

                if (fix) {
                    gpsCoords.setText(String.format("%.6f, %.6f", lat, lon));
                } else {
                    gpsCoords.setText("--");
                }

            } else if (uuid.equals(ACTIVITY_CHAR_UUID)) {
                JSONArray entries = json.optJSONArray("entries");
                if (entries != null && entries.length() > 0) {
                    // Accumulate networks instead of replacing
                    // Add new entries to front of list, avoiding duplicates by BSSID
                    for (int i = entries.length() - 1; i >= 0; i--) {
                        JSONObject entry = entries.getJSONObject(i);
                        String bssid = entry.optString("bssid", "");

                        // Check for duplicate
                        boolean exists = false;
                        for (NetworkItem existing : networkList) {
                            if (existing.getBssid().equals(bssid)) {
                                exists = true;
                                break;
                            }
                        }

                        if (!exists && !bssid.isEmpty()) {
                            NetworkItem item = new NetworkItem(
                                    entry.optString("ssid", "<hidden>"),
                                    bssid,
                                    entry.optString("channel", ""),
                                    entry.optString("signal", "")
                            );
                            networkList.add(0, item);  // Add to front
                        }
                    }

                    // Keep only last MAX_NETWORKS_DISPLAYED
                    while (networkList.size() > MAX_NETWORKS_DISPLAYED) {
                        networkList.remove(networkList.size() - 1);
                    }

                    networkAdapter.notifyDataSetChanged();
                }

            } else if (uuid.equals(CONFIG_CHAR_UUID)) {
                // Parse config: {"channel_mode":"common","channel_offset":"1","hop_interval":500}
                String mode = json.optString("channel_mode", "common");
                String offset = json.optString("channel_offset", "1");
                int interval = json.optInt("hop_interval", 500);

                // Only update UI if values changed
                if (!mode.equals(currentChannelMode) || !offset.equals(currentChannelOffset) || interval != currentHopInterval) {
                    currentChannelMode = mode;
                    currentChannelOffset = offset;
                    currentHopInterval = interval;

                    // Update spinners
                    channelModeSpinner.setSelection(mode.equals("all") ? 1 : 0);
                    channelOffsetSpinner.setSelection(offset.equals("1") ? 1 : 0);

                    Log.d(TAG, "Config updated: mode=" + mode + " offset=" + offset + " interval=" + interval);
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error parsing data: " + e.getMessage());
        }
    }

    private void setIndicatorColor(View view, int colorRes) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setShape(GradientDrawable.OVAL);
        drawable.setColor(ContextCompat.getColor(this, colorRes));
        view.setBackground(drawable);
    }

    private void updateConnectionStatus(String text, int colorRes) {
        connectionStatus.setText(text);
        connectionStatus.setTextColor(ContextCompat.getColor(this, colorRes));
    }

    private void updateScanControlButtons(boolean enabled) {
        if (startScanButton != null) startScanButton.setEnabled(enabled);
        if (stopScanButton != null) stopScanButton.setEnabled(enabled);
        if (saveConfigButton != null) saveConfigButton.setEnabled(enabled);
    }

    private void startRouterScan(int dwellMs) {
        if (wigleService == null || bluetoothGatt == null) {
            Toast.makeText(this, "Not connected", Toast.LENGTH_SHORT).show();
            return;
        }

        String cmd = "start:" + dwellMs;
        queueWrite(CONTROL_CHAR_UUID, cmd.getBytes());
        Toast.makeText(this, "Starting scanner...", Toast.LENGTH_SHORT).show();
        Log.d(TAG, "Queued start command: " + cmd);

        // Clear network list on new scan start
        networkList.clear();
        networkAdapter.notifyDataSetChanged();
    }

    private void stopRouterScan() {
        if (wigleService == null || bluetoothGatt == null) {
            Toast.makeText(this, "Not connected", Toast.LENGTH_SHORT).show();
            return;
        }

        String cmd = "stop";
        queueWrite(CONTROL_CHAR_UUID, cmd.getBytes());
        Toast.makeText(this, "Stopping scanner...", Toast.LENGTH_SHORT).show();
        Log.d(TAG, "Queued stop command");
    }

    private void saveConfig() {
        if (wigleService == null || bluetoothGatt == null) {
            Toast.makeText(this, "Not connected", Toast.LENGTH_SHORT).show();
            return;
        }

        // Get selected values from spinners
        String mode = channelModeSpinner.getSelectedItemPosition() == 0 ? "common" : "all";
        String offset = channelOffsetSpinner.getSelectedItemPosition() == 0 ? "0" : "1";

        // Format: "channel_mode:channel_offset:hop_interval"
        String cmd = mode + ":" + offset + ":" + currentHopInterval;

        queueWrite(CONFIG_CHAR_UUID, cmd.getBytes());
        Toast.makeText(this, "Saving config...", Toast.LENGTH_SHORT).show();
        Log.d(TAG, "Queued config save: " + cmd);
    }

    private void disconnect() {
        stopPolling();
        // Clear any pending BLE operations
        operationQueue.clear();
        isOperationPending = false;

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
        wigleService = null;

        updateConnectionStatus("Disconnected", R.color.status_stopped);
        connectButton.setText("Scan for Device");
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopPolling();
        disconnect();
    }
}
