BEGIN { OFS="\t" }

# Function to convert frequency to channel
function freq_to_chan(freq) {
    # 2.4GHz band
    if (freq >= 2412 && freq <= 2484) {
        if (freq == 2484) return 14
        return (freq - 2407) / 5
    }
    # 5GHz band
    if (freq >= 5170 && freq <= 5825) {
        return (freq - 5000) / 5
    }
    # 6GHz band (simplified)
    if (freq >= 5925 && freq <= 7125) {
        return (freq - 5950) / 5 + 1
    }
    return ""
}

/^BSS / {
    if (bssid != "") {
        if (enc == "") enc = "Open"
        if (ssid == "") ssid = "<hidden>"
        # Convert freq to channel if chan not set
        if (chan == "" && freq != "") {
            chan = freq_to_chan(freq)
        }
        if (chan != "") {
            print bssid, ssid, chan, sig, enc
        }
    }
    bssid = $2
    gsub(/\(.*/, "", bssid)
    ssid = ""
    chan = ""
    sig = ""
    enc = ""
    freq = ""
}

/^	SSID:/ {
    sub(/.*SSID: /, "")
    ssid = $0
}

/^	freq:/ {
    freq = $2
}

/primary channel:/ {
    chan = $NF
}

/DS Parameter set: channel/ {
    chan = $NF
}

/signal:/ {
    sig = $2
    gsub(/\..*/, "", sig)
}

/RSN:/ { enc = enc "WPA2 " }
/WPA:/ { enc = enc "WPA " }

END {
    if (bssid != "") {
        if (enc == "") enc = "Open"
        if (ssid == "") ssid = "<hidden>"
        if (chan == "" && freq != "") {
            chan = freq_to_chan(freq)
        }
        if (chan != "") {
            print bssid, ssid, chan, sig, enc
        }
    }
}
