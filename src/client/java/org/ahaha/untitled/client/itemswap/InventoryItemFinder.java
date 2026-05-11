package org.ahaha.untitled.client.itemswap;

import net.minecraft.entity.player.PlayerInventory;
import net.minecraft.item.Item;
import net.minecraft.item.ItemStack;

import java.util.OptionalInt;

public final class InventoryItemFinder {
    public static final int HOTBAR_SIZE = 9;
    public static final int MAIN_INVENTORY_SIZE = 36;

    public OptionalInt find(PlayerInventory inventory, Item item) {
        for (int slot = 0; slot < MAIN_INVENTORY_SIZE; slot++) {
            ItemStack stack = inventory.getStack(slot);
            if (stack.isOf(item)) {
                return OptionalInt.of(slot);
            }
        }

        return OptionalInt.empty();
    }

    public OptionalInt findInHotbar(PlayerInventory inventory, Item item) {
        for (int slot = 0; slot < HOTBAR_SIZE; slot++) {
            ItemStack stack = inventory.getStack(slot);
            if (stack.isOf(item)) {
                return OptionalInt.of(slot);
            }
        }

        return OptionalInt.empty();
    }

    public OptionalInt findEmptyHotbarSlot(PlayerInventory inventory) {
        for (int slot = 0; slot < HOTBAR_SIZE; slot++) {
            if (inventory.getStack(slot).isEmpty()) {
                return OptionalInt.of(slot);
            }
        }

        return OptionalInt.empty();
    }
}
