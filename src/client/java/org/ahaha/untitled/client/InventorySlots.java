package org.ahaha.untitled.client;

import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.player.PlayerInventory;
import net.minecraft.item.ItemStack;
import net.minecraft.network.packet.c2s.play.UpdateSelectedSlotC2SPacket;
import net.minecraft.registry.Registries;
import net.minecraft.screen.slot.SlotActionType;

final class InventorySlots {
    private static final int HOTBAR_SIZE = 9;
    private static final int MAIN_INVENTORY_START = 9;
    private static final int MAIN_INVENTORY_END = 36;

    private InventorySlots() {
    }

    static boolean matches(ItemStack stack, String itemId) {
        return !stack.isEmpty() && Registries.ITEM.getId(stack.getItem()).toString().equals(itemId);
    }

    static boolean isHotbarSlot(int slot) {
        return slot >= 0 && slot < HOTBAR_SIZE;
    }

    static int findHotbarSlot(PlayerInventory inventory, String itemId) {
        for (int slot = 0; slot < HOTBAR_SIZE; slot++) {
            if (matches(inventory.getStack(slot), itemId)) {
                return slot;
            }
        }
        return -1;
    }

    static int findMainInventorySlot(PlayerInventory inventory, String itemId) {
        for (int slot = MAIN_INVENTORY_START; slot < MAIN_INVENTORY_END; slot++) {
            if (matches(inventory.getStack(slot), itemId)) {
                return slot;
            }
        }
        return -1;
    }

    static int findEmptyHotbarSlot(PlayerInventory inventory, int protectedSlot) {
        for (int slot = 0; slot < HOTBAR_SIZE; slot++) {
            if (slot != protectedSlot && inventory.getStack(slot).isEmpty()) {
                return slot;
            }
        }
        return -1;
    }

    static int findReusableHotbarSlot(PlayerInventory inventory, int protectedSlot, String itemA, String itemB) {
        for (int slot = 0; slot < HOTBAR_SIZE; slot++) {
            ItemStack stack = inventory.getStack(slot);
            if (slot != protectedSlot && !matches(stack, itemA) && !matches(stack, itemB)) {
                return slot;
            }
        }
        return -1;
    }

    static boolean selectHotbarSlot(MinecraftClient client, int slot) {
        if (client.player == null || !isHotbarSlot(slot)) {
            return false;
        }
        client.player.getInventory().selectedSlot = slot;
        if (client.getNetworkHandler() != null) {
            client.getNetworkHandler().sendPacket(new UpdateSelectedSlotC2SPacket(slot));
        }
        return true;
    }

    static boolean swapWithHotbar(MinecraftClient client, int inventorySlot, int hotbarSlot) {
        if (client.player == null || client.interactionManager == null || !isHotbarSlot(hotbarSlot)) {
            return false;
        }

        int screenSlot = toPlayerScreenSlot(inventorySlot);
        if (screenSlot < 0) {
            return false;
        }

        client.interactionManager.clickSlot(
                client.player.currentScreenHandler.syncId,
                screenSlot,
                hotbarSlot,
                SlotActionType.SWAP,
                client.player
        );
        return true;
    }

    private static int toPlayerScreenSlot(int inventorySlot) {
        if (isHotbarSlot(inventorySlot)) {
            return 36 + inventorySlot;
        }
        if (inventorySlot >= MAIN_INVENTORY_START && inventorySlot < MAIN_INVENTORY_END) {
            return inventorySlot;
        }
        return -1;
    }
}
