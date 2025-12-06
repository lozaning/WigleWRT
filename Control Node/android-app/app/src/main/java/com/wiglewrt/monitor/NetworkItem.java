package com.wiglewrt.monitor;

public class NetworkItem {
    private String ssid;
    private String bssid;
    private String channel;
    private String signal;

    public NetworkItem(String ssid, String bssid, String channel, String signal) {
        this.ssid = ssid;
        this.bssid = bssid;
        this.channel = channel;
        this.signal = signal;
    }

    public String getSsid() {
        return ssid;
    }

    public String getBssid() {
        return bssid;
    }

    public String getChannel() {
        return channel;
    }

    public String getSignal() {
        return signal;
    }
}
