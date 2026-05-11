package org.ahaha.untitled.client;

import net.fabricmc.loader.api.FabricLoader;

import java.io.IOException;
import java.io.Reader;
import java.io.Writer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

final class ItemEffectLoopConfig {
    private static final String FILE_NAME = "untitled-item-swap.properties";

    final boolean enabled;
    final String itemA;
    final String itemB;
    final boolean allowInventorySwap;
    final int holdTicks;
    final int effectTicks;
    final int retryCooldownTicks;
    final int maxRetries;
    final boolean showMessages;

    private ItemEffectLoopConfig(
            boolean enabled,
            String itemA,
            String itemB,
            boolean allowInventorySwap,
            int holdTicks,
            int effectTicks,
            int retryCooldownTicks,
            int maxRetries,
            boolean showMessages
    ) {
        this.enabled = enabled;
        this.itemA = itemA;
        this.itemB = itemB;
        this.allowInventorySwap = allowInventorySwap;
        this.holdTicks = holdTicks;
        this.effectTicks = effectTicks;
        this.retryCooldownTicks = retryCooldownTicks;
        this.maxRetries = maxRetries;
        this.showMessages = showMessages;
    }

    static ItemEffectLoopConfig load() {
        Path path = FabricLoader.getInstance().getConfigDir().resolve(FILE_NAME);
        Properties properties = defaults();

        try {
            if (Files.notExists(path)) {
                writeDefaults(path, properties);
            } else {
                try (Reader reader = Files.newBufferedReader(path)) {
                    properties.load(reader);
                }
            }
        } catch (IOException ignored) {
            // Fall back to safe defaults when the config file is unavailable.
        }

        return new ItemEffectLoopConfig(
                parseBoolean(properties, "enabled", true),
                cleanItemId(properties.getProperty("itemA")),
                cleanItemId(properties.getProperty("itemB")),
                parseBoolean(properties, "allowInventorySwap", false),
                parseInt(properties, "holdTicks", 1, 1, 10),
                parseInt(properties, "effectTicks", 20, 1, 200),
                parseInt(properties, "retryCooldownTicks", 5, 1, 100),
                parseInt(properties, "maxRetries", 3, 0, 1000),
                parseBoolean(properties, "showMessages", true)
        );
    }

    boolean hasConfiguredItems() {
        return !itemA.isEmpty() && !itemB.isEmpty();
    }

    private static Properties defaults() {
        Properties properties = new Properties();
        properties.setProperty("enabled", "true");
        properties.setProperty("itemA", "");
        properties.setProperty("itemB", "");
        properties.setProperty("allowInventorySwap", "false");
        properties.setProperty("holdTicks", "1");
        properties.setProperty("effectTicks", "20");
        properties.setProperty("retryCooldownTicks", "5");
        properties.setProperty("maxRetries", "3");
        properties.setProperty("showMessages", "true");
        return properties;
    }

    private static void writeDefaults(Path path, Properties properties) throws IOException {
        Files.createDirectories(path.getParent());
        try (Writer writer = Files.newBufferedWriter(path)) {
            properties.store(writer, "Configure itemA/itemB as registry IDs. Use only where local/server rules allow automated item switching.");
        }
    }

    private static boolean parseBoolean(Properties properties, String key, boolean fallback) {
        String value = properties.getProperty(key);
        if (value == null) {
            return fallback;
        }
        return Boolean.parseBoolean(value.trim());
    }

    private static int parseInt(Properties properties, String key, int fallback, int min, int max) {
        String value = properties.getProperty(key);
        if (value == null) {
            return fallback;
        }

        try {
            int parsed = Integer.parseInt(value.trim());
            return Math.max(min, Math.min(max, parsed));
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    private static String cleanItemId(String value) {
        return value == null ? "" : value.trim();
    }
}
