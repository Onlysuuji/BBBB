package org.ahaha.untitled.client.itemswap;

import net.fabricmc.loader.api.FabricLoader;
import net.minecraft.item.Item;
import net.minecraft.registry.Registries;
import net.minecraft.util.Identifier;

import java.io.IOException;
import java.io.Reader;
import java.io.Writer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import java.util.Properties;

public final class ItemSwapConfig {
    private static final String CONFIG_FILE_NAME = "untitled-item-swap.properties";
    private static final String DEFAULT_ITEM_A = "minecraft:golden_apple";
    private static final String DEFAULT_ITEM_B = "minecraft:totem_of_undying";

    private final String itemAId;
    private final String itemBId;
    private final boolean allowInventorySwap;

    private ItemSwapConfig(String itemAId, String itemBId, boolean allowInventorySwap) {
        this.itemAId = itemAId;
        this.itemBId = itemBId;
        this.allowInventorySwap = allowInventorySwap;
    }

    public static ItemSwapConfig load() {
        Path path = FabricLoader.getInstance().getConfigDir().resolve(CONFIG_FILE_NAME);
        Properties properties = defaultProperties();

        if (Files.exists(path)) {
            try (Reader reader = Files.newBufferedReader(path)) {
                properties.load(reader);
            } catch (IOException ignored) {
                return fromProperties(properties);
            }
        } else {
            writeDefaults(path, properties);
        }

        return fromProperties(properties);
    }

    public Optional<Item> itemA() {
        return resolveItem(itemAId);
    }

    public Optional<Item> itemB() {
        return resolveItem(itemBId);
    }

    public boolean allowInventorySwap() {
        return allowInventorySwap;
    }

    private static Properties defaultProperties() {
        Properties properties = new Properties();
        properties.setProperty("itemA", DEFAULT_ITEM_A);
        properties.setProperty("itemB", DEFAULT_ITEM_B);
        properties.setProperty("allowInventorySwap", "true");
        return properties;
    }

    private static ItemSwapConfig fromProperties(Properties properties) {
        return new ItemSwapConfig(
                properties.getProperty("itemA", DEFAULT_ITEM_A).trim(),
                properties.getProperty("itemB", DEFAULT_ITEM_B).trim(),
                Boolean.parseBoolean(properties.getProperty("allowInventorySwap", "true").trim())
        );
    }

    private static void writeDefaults(Path path, Properties properties) {
        try {
            Files.createDirectories(path.getParent());
            try (Writer writer = Files.newBufferedWriter(path)) {
                properties.store(writer, "Untitled item A/B swap settings");
            }
        } catch (IOException ignored) {
        }
    }

    private static Optional<Item> resolveItem(String rawId) {
        Identifier id = Identifier.tryParse(rawId);
        if (id == null || !Registries.ITEM.containsId(id)) {
            return Optional.empty();
        }

        return Optional.of(Registries.ITEM.get(id));
    }
}
