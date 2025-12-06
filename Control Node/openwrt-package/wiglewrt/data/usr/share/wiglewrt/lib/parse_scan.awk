BEGIN { OFS="\t" }
/^BSS / {
    if (bssid != "") {
        if (enc == "") enc = "Open"
        if (ssid == "") ssid = "<hidden>"
        print bssid, ssid, chan, sig, enc
    }
    bssid = $2
    gsub(/\(.*/, "", bssid)
    ssid = ""
    chan = ""
    sig = ""
    enc = ""
}
/^	SSID:/ {
    sub(/.*SSID: /, "")
    ssid = $0
}
/primary channel:/ {
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
        print bssid, ssid, chan, sig, enc
    }
}
