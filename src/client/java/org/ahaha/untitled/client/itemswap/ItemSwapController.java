package org.ahaha.untitled.client.itemswap;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.entity.player.PlayerInventory;
import net.minecraft.item.Item;
import net.minecraft.item.ItemStack;
import net.minecraft.network.packet.c2s.play.UpdateSelectedSlotC2SPacket;
import net.minecraft.screen.slot.SlotActionType;

import java.util.Optional;
import java.util.OptionalInt;

public final class ItemSwapController {
    private final ItemSwapConfig config;
    private final InventoryItemFinder finder;

    public ItemSwapController(ItemSwapConfig config) {
        this.config = config;
        this.finder = new InventoryItemFinder();
    }

    public boolean toggle(MinecraftClient client) {
        if (client.player == null || client.interactionManager == null || client.currentScreen != null) {
            return false;
        }

        Optional<Item> itemA = config.itemA();
        Optional<Item> itemB = config.itemB();
        if (itemA.isEmpty() || itemB.isEmpty()) {
            return false;
        }

        ClientPlayerEntity player = client.player;
        PlayerInventory inventory = player.getInventory();
        Item target = targetItem(inventory.getStack(inventory.selectedSlot), itemA.get(), itemB.get());
        OptionalInt targetSlot = finder.find(inventory, target);
        if (targetSlot.isEmpty()) {
            return false;
        }

        return switchToSlot(client, player, inventory, targetSlot.getAsInt(), itemA.get(), itemB.get());
    }

    private Item targetItem(ItemStack selectedStack, Item itemA, Item itemB) {
        if (selectedStack.isOf(itemA)) {
            return itemB;
        }
        if (selectedStack.isOf(itemB)) {
            return itemA;
        }

        return itemA;
    }

    private boolean switchToSlot(
            MinecraftClient client,
            ClientPlayerEntity player,
            PlayerInventory inventory,
            int inventorySlot,
            Item itemA,
            Item itemB
    ) {
        if (inventorySlot < InventoryItemFinder.HOTBAR_SIZE) {
            selectHotbarSlot(client, inventory, inventorySlot);
            return true;
        }

        if (!config.allowInventorySwap()) {
            return false;
        }

        OptionalInt destinationSlot = safeHotbarDestination(inventory, itemA, itemB);
        if (destinationSlot.isEmpty()) {
            return false;
        }

        client.interactionManager.clickSlot(
                player.playerScreenHandler.syncId,
                inventorySlot,
                destinationSlot.getAsInt(),
                SlotActionType.SWAP,
                player
        );
        selectHotbarSlot(client, inventory, destinationSlot.getAsInt());
        return true;
    }

    private OptionalInt safeHotbarDestination(PlayerInventory inventory, Item itemA, Item itemB) {
        ItemStack selectedStack = inventory.getStack(inventory.selectedSlot);
        if (selectedStack.isEmpty() || selectedStack.isOf(itemA) || selectedStack.isOf(itemB)) {
            return OptionalInt.of(inventory.selectedSlot);
        }

        return finder.findEmptyHotbarSlot(inventory);
    }

    private void selectHotbarSlot(MinecraftClient client, PlayerInventory inventory, int slot) {
        if (inventory.selectedSlot == slot) {
            return;
        }

        inventory.selectedSlot = slot;
        client.getNetworkHandler().sendPacket(new UpdateSelectedSlotC2SPacket(slot));
    }
}
