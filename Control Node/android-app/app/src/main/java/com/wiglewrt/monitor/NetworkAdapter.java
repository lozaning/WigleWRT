package com.wiglewrt.monitor;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.List;

public class NetworkAdapter extends RecyclerView.Adapter<NetworkAdapter.ViewHolder> {
    private List<NetworkItem> networkList;

    public NetworkAdapter(List<NetworkItem> networkList) {
        this.networkList = networkList;
    }

    @NonNull
    @Override
    public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
                .inflate(R.layout.item_network, parent, false);
        return new ViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
        NetworkItem item = networkList.get(position);
        holder.ssid.setText(item.getSsid().isEmpty() ? "<hidden>" : item.getSsid());
        holder.bssid.setText(item.getBssid());
        holder.channel.setText("Ch " + item.getChannel());
        holder.signal.setText(item.getSignal() + " dBm");
    }

    @Override
    public int getItemCount() {
        return networkList.size();
    }

    public static class ViewHolder extends RecyclerView.ViewHolder {
        TextView ssid;
        TextView bssid;
        TextView channel;
        TextView signal;

        public ViewHolder(View itemView) {
            super(itemView);
            ssid = itemView.findViewById(R.id.networkSsid);
            bssid = itemView.findViewById(R.id.networkBssid);
            channel = itemView.findViewById(R.id.networkChannel);
            signal = itemView.findViewById(R.id.networkSignal);
        }
    }
}
