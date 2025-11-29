package com.wiglewrt.monitor;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.List;

public class ActivityAdapter extends RecyclerView.Adapter<ActivityAdapter.ViewHolder> {

    private List<MainActivity.NetworkEntry> entries = new ArrayList<>();

    public void setEntries(List<MainActivity.NetworkEntry> entries) {
        this.entries = entries;
        notifyDataSetChanged();
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
        MainActivity.NetworkEntry entry = entries.get(position);
        holder.bind(entry);
    }

    @Override
    public int getItemCount() {
        return entries.size();
    }

    static class ViewHolder extends RecyclerView.ViewHolder {
        private final TextView tvIndicator;
        private final TextView tvSsid;
        private final TextView tvBssid;
        private final TextView tvDetails;

        ViewHolder(@NonNull View itemView) {
            super(itemView);
            tvIndicator = itemView.findViewById(R.id.tvIndicator);
            tvSsid = itemView.findViewById(R.id.tvSsid);
            tvBssid = itemView.findViewById(R.id.tvBssid);
            tvDetails = itemView.findViewById(R.id.tvDetails);
        }

        void bind(MainActivity.NetworkEntry entry) {
            // New indicator
            if (entry.isNew) {
                tvIndicator.setText("*");
                tvIndicator.setTextColor(itemView.getContext().getColor(R.color.new_network));
            } else {
                tvIndicator.setText("o");
                tvIndicator.setTextColor(itemView.getContext().getColor(R.color.text_secondary));
            }

            // SSID
            tvSsid.setText(entry.ssid);

            // BSSID
            tvBssid.setText(entry.bssid);

            // Details (channel, signal, time)
            String details = String.format("Ch %s | %s dBm | %s",
                    entry.channel, entry.signal, formatTime(entry.timestamp));
            tvDetails.setText(details);

            // Signal color
            int signalColor = getSignalColor(entry.signal);
            tvDetails.setTextColor(itemView.getContext().getColor(signalColor));
        }

        private String formatTime(String timestamp) {
            if (timestamp == null || timestamp.isEmpty()) return "-";
            // Return just the time part if full timestamp
            if (timestamp.contains(" ")) {
                return timestamp.split(" ")[1];
            }
            return timestamp;
        }

        private int getSignalColor(String signal) {
            try {
                int sig = Integer.parseInt(signal);
                if (sig >= -50) return R.color.signal_excellent;
                if (sig >= -60) return R.color.signal_good;
                if (sig >= -70) return R.color.signal_fair;
                return R.color.signal_poor;
            } catch (NumberFormatException e) {
                return R.color.text_secondary;
            }
        }
    }
}
