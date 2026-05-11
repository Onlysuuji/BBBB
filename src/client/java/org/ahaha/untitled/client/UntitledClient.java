package org.ahaha.untitled.client;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keybinding.v1.KeyBindingHelper;
import net.minecraft.client.option.KeyBinding;
import net.minecraft.client.util.InputUtil;
import org.lwjgl.glfw.GLFW;

public class UntitledClient implements ClientModInitializer {
    private final ItemEffectLoopController effectLoopController = new ItemEffectLoopController();
    private KeyBinding toggleEffectLoopKey;

    @Override
    public void onInitializeClient() {
        toggleEffectLoopKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.untitled.toggle_effect_loop",
                InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_H,
                "category.untitled"
        ));

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            while (toggleEffectLoopKey.wasPressed()) {
                effectLoopController.toggleEnabled(client);
            }

            effectLoopController.tick(client);
        });
    }
}
