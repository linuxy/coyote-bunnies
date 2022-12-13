const std = @import("std");
const ecs = @import("coyote-ecs");
var random: std.rand.DefaultPrng = undefined;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const World = ecs.World;
const Entity = ecs.Entity;
const Cast = ecs.Cast;
const Systems = ecs.Systems;

const allocator = std.heap.c_allocator;
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;
const BUNNY_WIDTH = 32;
const BUNNY_HEIGHT = 32;
const MAX_DIST = 8;
const START_SIZE = 20;

pub fn main() !void {
    var world = try World.create();
    defer world.destroy();

    var game = try Game.init(world);
    defer game.deinit();

    while(game.isRunning) {
        try game.handleEvents();
        try Systems.run(Update, .{world, game});
        try Systems.run(Render, .{world, game});
    }
}

pub const Game = struct {
    world: *World,

    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,

    bunny_texture: ?*c.SDL_Texture,
    font: ?*c.TTF_Font,

    leftMouseHeld: bool,
    rightMouseHeld: bool,
    mouseX: c_int,
    mouseY: c_int,
    bunnies_pre: u32,
    bunnies_post: u32,
    bunnies_start: i64,
    game_start: i64,
    frame_num: i64,
    last_frame: i64,
    last_fps: i64,
    last_update: i64,

    screenWidth: c_int,
    screenHeight: c_int,
    isRunning: bool,
    
    pub fn init(world: *World) !*Game {
        var self = try allocator.create(Game);
        self.world = world;
        random = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp()));
        
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }

        self.window = c.SDL_CreateWindow("Coyote Bunnies Benchmark", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH, SCREEN_HEIGHT, c.SDL_WINDOW_OPENGL) orelse
        {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        self.renderer = c.SDL_CreateRenderer(self.window, -1, 0) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        if(c.TTF_Init() != 0) {
            c.SDL_Log("Unable to initialized fonts: %s", c.SDL_GetError());
            return error.SDLFontInitializationFailed;
        }

        self.font = c.TTF_OpenFont("assets/fonts/mecha.ttf", 20);
        
        self.bunny_texture = try loadTexture(self, "assets/images/bunny.png");
        self.isRunning = true;
        self.frame_num = 0;
        self.last_frame = 0;
        self.game_start = std.time.milliTimestamp();
        self.last_fps = 0;
        self.last_update = 0;

        return self;
    }

    pub fn handleEvents(self: *Game) !void {
        var event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&event) != 0) {
            _ = c.SDL_GetMouseState(&self.mouseX, &self.mouseY);
            switch (event.@"type") {
                c.SDL_QUIT => {
                    self.isRunning = false;
                },
                c.SDL_MOUSEBUTTONDOWN => {
                    if(event.button.button == c.SDL_BUTTON_LEFT) {
                        self.leftMouseHeld = true;
                    }
                    if(event.button.button == c.SDL_BUTTON_RIGHT) {
                        self.rightMouseHeld = true;
                    }
                },
                c.SDL_MOUSEBUTTONUP => {
                    if(event.button.button == c.SDL_BUTTON_LEFT) {
                        self.leftMouseHeld = false;
                    }
                    if(event.button.button == c.SDL_BUTTON_RIGHT) {
                        self.rightMouseHeld = false;
                    }
                },
                c.SDL_KEYDOWN => {
                    switch(event.key.keysym.sym) {
                        else => std.log.info("Unhandled key was pressed: {}", .{event.key.keysym.sym}),
                    }
                },
                else => {},
            }
        }
        if(self.leftMouseHeld) {
            try addBunny(self.world, self.mouseX, self.mouseY);
        }
        //else if doesn't exist in -Drelease-fast apparently
        if(self.rightMouseHeld) {
            try removeBunny(self.world);
        }
    }

    pub fn deinit(self: *Game) void {
        self.isRunning = false;
        c.TTF_CloseFont(self.font);
        c.TTF_Quit();
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_QuitSubSystem(c.SDL_INIT_VIDEO);
        c.SDL_Quit();
        defer allocator.destroy(self);
        //Segfault for some reason on exit
    }
};

//Components
pub const Components = struct {

    pub const Position = struct {
        x: f64 = 0.0,
        y: f64 = 0.0,
        in_motion: bool = false,
        speed: @Vector(2, f64) = @Vector(2, f64){0, 0},
        color: @Vector(3, u8) = @Vector(3, u8){0, 0, 0},
        time: Time = .{.updated = 0,
                       .delta = 0.0},
    };

};

pub const Time = struct {
    updated: u32 = 0,
    delta: f64 = 0.0,
};

pub const Direction = enum {
    U,
    D,
    L,
    R
};

//Systems
pub fn Render(world: *World, game: *Game) !void {

    _ = c.SDL_RenderClear(game.renderer);
    _ = c.SDL_SetRenderDrawColor(game.renderer, 255, 255, 255, 255);

    //Render Bunnies
    //var start = std.time.milliTimestamp();
    var bunnies = world.components.iterator();
    while(bunnies.next()) |bunny| 
    {
        if(bunny.magic != ecs.MAGIC)
            continue;

        var position = Cast(Components.Position, bunny);
        try renderToScreen(game, game.bunny_texture, @floatToInt(c_int, @round(position.x)), @floatToInt(c_int, @round(position.y)), position.color);
    }
    //std.log.info("Rendered bunnies in {}ms", .{std.time.milliTimestamp() - start});

    var ibuf: [0x100]u8 = std.mem.zeroes([0x100]u8);
    const int_buf = ibuf[0..];

    var ibuf2: [0x100]u8 = std.mem.zeroes([0x100]u8);
    const int2_buf = ibuf2[0..];

    //Render Stats
    var bar_rect: c.SDL_Rect = undefined;
    bar_rect.x = 0;
    bar_rect.y = 0;
    bar_rect.w = SCREEN_WIDTH;
    bar_rect.h = 40;

    _ = c.SDL_SetRenderDrawColor(game.renderer, 0, 0, 0, 0);
    _ = c.SDL_RenderFillRect(game.renderer, &bar_rect);
    _ = c.SDL_SetRenderDrawColor(game.renderer, 255, 255, 255, 255);

    var color = c.SDL_Color{.r = 255, .g = 100, .b = 255, .a = 0 };
    var new_fps: i64 = 0;
    if(std.time.milliTimestamp() - game.last_update > 1000) {
        new_fps = game.frame_num - game.last_frame;
        game.last_frame = game.frame_num;
        game.last_fps = new_fps;
        game.last_update = std.time.milliTimestamp();
    } else {
        new_fps = game.last_fps;
    }
    var fps = std.fmt.bufPrintIntToSlice(int_buf, new_fps, 10, .lower, .{})[0..];
    _ = std.fmt.bufPrintIntToSlice(int2_buf, world.components.count(), 10, .lower, .{});
    var text = try std.mem.concat(allocator, u8, &[_][]const u8{fps, " FPS      Coyote-ECS    Bunnies: ", int2_buf});

    var surface = c.TTF_RenderText_Solid(game.font, @ptrCast([*c]u8, text), color);
    var texture = c.SDL_CreateTextureFromSurface(game.renderer, surface);
    var textW: c_int = 0;
    var textH: c_int = 0;
    _ = c.SDL_QueryTexture(texture, null, null, &textW, &textH);
    var dest_text = c.SDL_Rect{.x = 10, .y = 10, .w = textW, .h = textH};
    _ = c.SDL_RenderCopy(game.renderer, texture, null, &dest_text);

    c.SDL_RenderPresent(game.renderer);
    c.SDL_DestroyTexture(texture);
    c.SDL_FreeSurface(surface);
    game.frame_num += 1;
}

pub fn Update(world: *World, game: *Game) !void {
    //Update player entity
    _ = game;
    try updateSpaceTime(world);
}

//Prefer component iterators to entity
pub inline fn updateSpaceTime(world: *World) !void {
    var it = world.components.iteratorFilter(Components.Position);
    var i: u32 = 0;

    //var start = std.time.milliTimestamp();
    while(it.next()) |component| : (i += 1) {
        if(component.attached) {
            var position = Cast(Components.Position, component);
            var last_update = position.time.updated;
            var delta = @intToFloat(f64, c.SDL_GetTicks() - last_update) / 1000.0;
            //Works correctly on stage2 not stage1
            //try component.set(Components.Position, .{ .speed_delta = speed_delta, .time = .{.updated = c.SDL_GetTicks(), .delta = delta} });

            position.x += position.speed[0];
            position.y += position.speed[1];

            if(position.x + BUNNY_WIDTH / 2 > SCREEN_WIDTH or position.x + BUNNY_WIDTH/2 < 0)
                position.speed[0] *= -1;

            if(position.y + BUNNY_HEIGHT / 2 > SCREEN_HEIGHT or position.y + BUNNY_HEIGHT/2 - 40 < 0)
                position.speed[1] *= -1;

            position.time.updated = c.SDL_GetTicks();
            position.time.delta = delta;
        }
    }
    //std.log.info("Updated {} bunnies in {}ms.", .{i, std.time.milliTimestamp() - start});
}

pub inline fn addBunny(world: *World, x: c_int, y: c_int) !void {
    var i: usize = 0;
    while(i < 1000) : (i += 1) {
        var bunny = try world.entities.create();
        var position = try world.components.create(Components.Position);
        try bunny.attach(position, Components.Position{
            .x = @intToFloat(f64, x),
            .y = @intToFloat(f64, y),
            .speed = @Vector(2,f64){@intToFloat(f64, random.random().intRangeLessThan(i64, -250, 250)) / 60.0,
                                    @intToFloat(f64, random.random().intRangeLessThan(i64, -250, 250)) / 60.0},
            .color = @Vector(3,u8){random.random().intRangeLessThan(u8, 50, 240),
                                   random.random().intRangeLessThan(u8, 80, 240),
                                   random.random().intRangeLessThan(u8, 100, 240)}
        });
    }
}

pub inline fn removeBunny(world: *World) !void {
    var it = world.components.iterator();
    var i: u32 = 0;
    while(it.next()) |component| : (i += 1) {
        if(i < 1000) {
            component.destroy();
        } else {
            break;
        }
    }
}

pub inline fn renderToScreen(game: *Game, texture: ?*c.SDL_Texture, x: c_int, y: c_int, rgb: @Vector(3, u8)) !void {
    var src_rect: c.SDL_Rect = undefined;
    var dest_rect: c.SDL_Rect = undefined;

    src_rect.x = 0;
    src_rect.y = 0;
    src_rect.w = BUNNY_WIDTH;
    src_rect.h = BUNNY_HEIGHT;

    dest_rect.x = x;
    dest_rect.y = y;
    dest_rect.w = BUNNY_WIDTH;
    dest_rect.h = BUNNY_HEIGHT;

    _ = c.SDL_SetTextureColorMod(texture, rgb[0], rgb[1], rgb[2]);
    if(c.SDL_RenderCopyEx(game.renderer, texture, &src_rect, &dest_rect, 0, 0, c.SDL_FLIP_NONE) != 0) {
        c.SDL_Log("Unable to render copy: %s", c.SDL_GetError());
        return error.SDL_RenderCopyExFailed;
    }
}

pub inline fn loadTexture(game: *Game, path: []const u8) !?*c.SDL_Texture {
    var texture = c.IMG_LoadTexture(game.renderer, @ptrCast([*c]const u8, path)) orelse
    {
        c.SDL_Log("Unable load image: %s", c.SDL_GetError());
        return error.SDL_LoadTextureFailed;
    };

    return texture;
}
