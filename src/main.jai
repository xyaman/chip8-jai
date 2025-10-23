#import "Basic";
#import "File";
#import "SDL";
System :: #import "System";

Chip8 :: struct {
    v: [16]u8;          // 16 general purpose 8-bit registers
    pc: u16;            // program counter
    i: u16;             // index register
    sp: u8;             // stack pointer
    stack: [16]u16;
    display: [64][32]u8;
    memory: [4096]u8;
}

chip8_load_rom :: (chip8: *Chip8, filename: string) -> bool {
    file, success := file_open(filename);
    if !success {
        return false;
    }

    length := file_length(file);

    // 0x000 to 0x1FF: reserved for the interpreter
    // 0x200: 512
    success = file_read(file, *chip8.memory[512], length);
    if !success {
        return false;
    }

    // reset program counter
    chip8.pc = 512;
    return true;
}

chip8_next_instruction :: (chip8: *Chip8) -> handled := true {

    assert(chip8.pc < 4096);
    // opcode: 16 bits (2 bytes)
    top := cast(u16) chip8.memory[chip8.pc];
    bot := cast(u16) chip8.memory[chip8.pc+1];
    opcode := (top << 8) | bot;

    chip8.pc += 2;

    if (opcode & 0xf000) == {
        case 0x0000;
            if opcode == {
            // 00E0 - CLS
            // Clear the display.
            case 0x00e0;
                for x: 0..chip8.display.count-1 {
                    for y: 0..chip8.display[x].count-1 {
                        chip8.display[x][y] = 0;
                    }
                }

            // 00EE - RET
            // Return from a subroutine.
            // The interpreter sets the program counter to the address at the top of the stack, then subtracts 1 from the stack pointer.
            case 0x00ee;
                log_error("Unhandled opcode: %\n",  formatInt(opcode, base=16, minimum_digits=4));
                return false;
            case;
                log_error("Unknown opcode: %\n",  formatInt(opcode, base=16, minimum_digits=4));
                return false;
            }

        // 1nnn - JP addr
        // Jump to location nnn.
        // The interpreter sets the program counter to nnn.
        case 0x1000;
            nnn := opcode & 0x0fff;
            chip8.pc = nnn;

        // 5xkk - LD Vx, byte
        // Set Vx = kk.
        // The interpreter puts the value kk into register Vx.
        case 0x6000;
            x := (opcode & 0x0f00) >> 8;
            kk := opcode & 0x00ff;
            chip8.v[x] = cast(u8) kk;

        // 7xkk - ADD Vx, byte
        // Set Vx = Vx + kk.
        // Adds the value kk to the value of register Vx, then stores the result in Vx.
        case 0x7000;
            x := (opcode & 0x0f00) >> 8;
            kk := opcode & 0x00ff;
            chip8.v[x] += cast(u8) kk;

        // Annn - LD I, addr
        // Set I = nnn.
        // The value of register I is set to nnn.
        case 0xa000;
            chip8.i = opcode & 0x0fff;

        // Dxyn - DRW Vx, Vy, nibble
        // Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision.
        // The interpreter reads n bytes from memory, starting at the address stored in I. These bytes are then displayed as sprites on screen at coordinates (Vx, Vy). Sprites are XORed onto the existing screen. If this causes any pixels to be erased, VF is set to 1, otherwise it is set to 0. If the sprite is positioned so part of it is outside the coordinates of the display, it wraps around to the opposite side of the screen.
        // See instruction 8xy3 for more information on XOR.
        // Note:
        //  - width: 8 cells (1 byte)
        //  - height: n
        case 0xd000;
            vx := chip8.v[(opcode & 0x0f00) >> 8];
            vy := chip8.v[(opcode & 0x00f0) >> 4];

            h := opcode & 0x000f;
            w :: 8;

            chip8.v[0xf] = 0;
            for y: 0..h-1 {
                sprite := chip8.memory[chip8.i + y];
                for x: 0..w-1 {
                    // 0x80 => 1000 0000
                    pixel_on := sprite & (0x80 >> x);
                    if pixel_on > 0 {
                        // display[(vx + x) % 64][(vy + y) % 32]

                        // activate collision flag if there was already a value before
                        ifx chip8.display[vx + x][vy + y] then chip8.v[0xf] = 1;

                        // xor into display
                        chip8.display[vx + x][vy + y] ^= 1;
                    }

                }
            }

        case;
            log_error("Unhandled opcode: %\n",  formatInt(opcode, base=16, minimum_digits=4));
            return false;
    }

    return true;
}

main :: () {

    args := get_command_line_arguments();
    defer array_free(args);

    if args.count < 2 {
        print("error: ROM path missing.\n");
        print("usage: % <rom_filepath>\n", args[0]);
        exit(1);
    }

    chip8: Chip8;
    success := chip8_load_rom(*chip8, args[1]);
    if !success {
        print("Error when loading rom: %\n");
        exit(1);
    }


    if SDL_Init(SDL_INIT_VIDEO) != 0 {
        log_error("Error running SDL_INIT: %\n", to_string(SDL_GetError()));
        return;
    }

    w := SDL_CreateWindow("Chip8", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 640, 320, SDL_WINDOW_OPENGL|SDL_WINDOW_SHOWN);
    if w == null {
        log_error("Could not create window: %\n", to_string(SDL_GetError()));
        return;
    }

    r := SDL_CreateRenderer(w, -1, 0);
    if r == null {
        log_error("Could not create renderer: %\n", to_string(SDL_GetError()));
        return;
    }

    event_handled := true;
    running := true;
    while (running) {

        // debug: we stop execution processor execution, but still see the window
        // until we manually close it
        if event_handled {
            event_handled = chip8_next_instruction(*chip8);
        }

        event: SDL_Event;
        while SDL_PollEvent(*event) {
            if event.type == {
                case SDL_QUIT; running = false;
            }
        }

        // render chip display
        SDL_RenderClear(r);
        for x: 0..63 {
            for y: 0..31 {
                on := chip8.display[x][y] > 0;
                if on {
                    SDL_SetRenderDrawColor(r, 255, 255, 255, 1);
                } else {
                    SDL_SetRenderDrawColor(r, 0, 0, 0, 1);
                }

                cell := SDL_Rect.{xx (x * 10), xx (y * 10), 10, 10};
                SDL_RenderFillRect(r, *cell);
            }
        }

        SDL_RenderPresent(r);
        SDL_Delay(2);
    }
}
