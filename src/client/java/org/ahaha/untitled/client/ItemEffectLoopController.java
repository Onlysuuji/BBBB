package org.ahaha.untitled.client;

import net.minecraft.client.MinecraftClient;
import net.minecraft.text.Text;

final class ItemEffectLoopController {
    private enum State {
        IDLE,
        HOLDING_A,
        MAINTAINING_B,
        COOLDOWN
    }

    private ItemEffectLoopConfig config = ItemEffectLoopConfig.load();
    private boolean runtimeEnabled = config.enabled;
    private State state = State.IDLE;
    private int ticksRemaining;
    private int bHotbarSlot = -1;
    private int aHotbarSlot = -1;
    private int movedAOriginalInventorySlot = -1;
    private int movedAHotbarSlot = -1;
    private int retries;
    private boolean pausedUntilUseReleased;
    private boolean warnedAboutRules;

    void toggleEnabled(MinecraftClient client) {
        config = ItemEffectLoopConfig.load();
        runtimeEnabled = !runtimeEnabled || pausedUntilUseReleased;
        pausedUntilUseReleased = false;

        if (runtimeEnabled) {
            send(client, "Untitled effect loop enabled. Check local/server rules before use.");
        } else {
            stop(client, true);
            send(client, "Untitled effect loop disabled.");
        }
    }

    void tick(MinecraftClient client) {
        if (client == null || client.player == null) {
            resetState();
            return;
        }
        if (client.interactionManager == null || client.currentScreen != null) {
            return;
        }

        if (!runtimeEnabled || !config.hasConfiguredItems()) {
            stop(client, false);
            return;
        }

        boolean usePressed = client.options.useKey.isPressed();
        if (!usePressed) {
            pausedUntilUseReleased = false;
            if (state != State.IDLE) {
                stop(client, true);
            }
            return;
        }

        if (pausedUntilUseReleased) {
            return;
        }

        switch (state) {
            case IDLE -> {
                if (isSelectedItemB(client)) {
                    startCycle(client);
                }
            }
            case HOLDING_A -> tickHoldingA(client);
            case MAINTAINING_B -> tickMaintainingB(client);
            case COOLDOWN -> tickCooldown(client);
        }
    }

    private void startCycle(MinecraftClient client) {
        if (!isClientReady(client) || client.player == null) {
            failOrPause(client, "Effect loop stopped: client is not ready.");
            return;
        }

        int selectedSlot = client.player.getInventory().selectedSlot;
        if (!InventorySlots.isHotbarSlot(selectedSlot)
                || !InventorySlots.matches(client.player.getInventory().getStack(selectedSlot), config.itemB)) {
            failOrPause(client, "Effect loop stopped: itemB is no longer selected.");
            return;
        }

        bHotbarSlot = selectedSlot;
        aHotbarSlot = InventorySlots.findHotbarSlot(client.player.getInventory(), config.itemA);
        if (aHotbarSlot < 0 && config.allowInventorySwap) {
            aHotbarSlot = moveItemAToHotbar(client, bHotbarSlot);
        }

        if (aHotbarSlot < 0) {
            failOrPause(client, "Effect loop retry failed: itemA was not found.");
            return;
        }

        if (!InventorySlots.selectHotbarSlot(client, aHotbarSlot)) {
            failOrPause(client, "Effect loop retry failed: itemA could not be selected.");
            return;
        }

        if (!warnedAboutRules) {
            warnedAboutRules = true;
            send(client, "Effect loop is timing dependent. Use only where rules allow it.");
        }

        state = State.HOLDING_A;
        ticksRemaining = config.holdTicks;
    }

    private int moveItemAToHotbar(MinecraftClient client, int protectedBSlot) {
        if (client.player == null || client.interactionManager == null || client.currentScreen != null) {
            return -1;
        }

        int inventorySlot = InventorySlots.findMainInventorySlot(client.player.getInventory(), config.itemA);
        if (inventorySlot < 0) {
            return -1;
        }

        int targetHotbarSlot = InventorySlots.findEmptyHotbarSlot(client.player.getInventory(), protectedBSlot);
        if (targetHotbarSlot < 0) {
            targetHotbarSlot = InventorySlots.findReusableHotbarSlot(client.player.getInventory(), protectedBSlot, config.itemA, config.itemB);
        }
        if (targetHotbarSlot < 0) {
            return -1;
        }

        if (!InventorySlots.swapWithHotbar(client, inventorySlot, targetHotbarSlot)) {
            return -1;
        }

        movedAOriginalInventorySlot = inventorySlot;
        movedAHotbarSlot = targetHotbarSlot;
        return targetHotbarSlot;
    }

    private void tickHoldingA(MinecraftClient client) {
        if (!canContinueCycle(client)) {
            failOrPause(client, "Effect loop stopped: itemA/itemB condition changed.");
            return;
        }

        ticksRemaining--;
        if (ticksRemaining > 0) {
            return;
        }

        if (!InventorySlots.selectHotbarSlot(client, bHotbarSlot)) {
            failOrPause(client, "Effect loop stopped: itemB could not be restored.");
            return;
        }

        state = State.MAINTAINING_B;
        ticksRemaining = config.effectTicks;
    }

    private void tickMaintainingB(MinecraftClient client) {
        if (!canContinueCycle(client) || !isSelectedItemB(client)) {
            failOrPause(client, "Effect loop stopped: itemB condition changed.");
            return;
        }

        ticksRemaining--;
        if (ticksRemaining > 0) {
            return;
        }

        if (retries >= config.maxRetries) {
            pausedUntilUseReleased = true;
            stop(client, true);
            send(client, "Effect loop stopped: retry limit reached.");
            return;
        }

        retries++;
        startCycle(client);
    }

    private void tickCooldown(MinecraftClient client) {
        ticksRemaining--;
        if (ticksRemaining <= 0) {
            state = State.IDLE;
        }
    }

    private boolean canContinueCycle(MinecraftClient client) {
        return isClientReady(client)
                && client.player != null
                && InventorySlots.isHotbarSlot(aHotbarSlot)
                && InventorySlots.isHotbarSlot(bHotbarSlot)
                && InventorySlots.matches(client.player.getInventory().getStack(aHotbarSlot), config.itemA)
                && InventorySlots.matches(client.player.getInventory().getStack(bHotbarSlot), config.itemB);
    }

    private boolean isSelectedItemB(MinecraftClient client) {
        return client.player != null
                && InventorySlots.matches(
                client.player.getInventory().getStack(client.player.getInventory().selectedSlot),
                config.itemB
        );
    }

    private boolean isClientReady(MinecraftClient client) {
        return client != null
                && client.player != null
                && client.interactionManager != null
                && client.currentScreen == null;
    }

    private void failOrPause(MinecraftClient client, String message) {
        retries++;
        returnToItemB(client);
        restoreMovedItemA(client);

        if (retries > config.maxRetries) {
            pausedUntilUseReleased = true;
            resetState();
            send(client, message);
            return;
        }

        state = State.COOLDOWN;
        ticksRemaining = config.retryCooldownTicks;
        send(client, message);
    }

    private void stop(MinecraftClient client, boolean restoreMovedItem) {
        if (restoreMovedItem) {
            returnToItemB(client);
            restoreMovedItemA(client);
        }
        resetState();
    }

    private void restoreMovedItemA(MinecraftClient client) {
        if (movedAOriginalInventorySlot < 0 || movedAHotbarSlot < 0 || !isClientReady(client) || client.player == null) {
            movedAOriginalInventorySlot = -1;
            movedAHotbarSlot = -1;
            return;
        }

        if (InventorySlots.matches(client.player.getInventory().getStack(movedAHotbarSlot), config.itemA)) {
            InventorySlots.swapWithHotbar(client, movedAOriginalInventorySlot, movedAHotbarSlot);
        }

        movedAOriginalInventorySlot = -1;
        movedAHotbarSlot = -1;
    }

    private void returnToItemB(MinecraftClient client) {
        if (isClientReady(client)
                && client.player != null
                && InventorySlots.isHotbarSlot(bHotbarSlot)
                && InventorySlots.matches(client.player.getInventory().getStack(bHotbarSlot), config.itemB)) {
            InventorySlots.selectHotbarSlot(client, bHotbarSlot);
        }
    }

    private void resetState() {
        state = State.IDLE;
        ticksRemaining = 0;
        bHotbarSlot = -1;
        aHotbarSlot = -1;
        retries = 0;
    }

    private void send(MinecraftClient client, String message) {
        if (config.showMessages && client != null && client.player != null) {
            client.player.sendMessage(Text.literal(message), true);
        }
    }

}
