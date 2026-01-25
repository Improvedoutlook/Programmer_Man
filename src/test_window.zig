//! Simple raylib window test
const rl = @import("raylib");

pub fn main() !void {
    rl.initWindow(800, 600, "TEST WINDOW - If you see this, raylib works!");
    defer rl.closeWindow();
    
    rl.setTargetFPS(60);
    
    var counter: i32 = 0;
    
    while (!rl.windowShouldClose()) {
        counter += 1;
        
        rl.beginDrawing();
        defer rl.endDrawing();
        
        rl.clearBackground(rl.Color.ray_white);
        rl.drawText("RAYLIB WINDOW TEST", 250, 200, 40, rl.Color.dark_gray);
        rl.drawText("If you can see this, the window is working!", 150, 300, 20, rl.Color.maroon);
        rl.drawText("Press ESC to close", 280, 350, 20, rl.Color.gray);
        
        var buf: [64]u8 = undefined;
        const counter_text = @import("std").fmt.bufPrintZ(&buf, "Frame: {d}", .{counter}) catch "Frame: ???";
        rl.drawText(counter_text, 350, 400, 20, rl.Color.blue);
    }
}
