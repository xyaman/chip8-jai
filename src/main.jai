#import "Basic";
#import "File";
#import "SDL";
System :: #import "System";

Chip8 :: struct {
    v: [16]u8;          // 16 general purpose 8-bit registers
    pc: u16;            // program counter
    i: u16;             // index register
    sp: u8;             // stack pointer
    tr: u8;             // delay register
    stack: [16]u16;
    keyboard: [16]u8;
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


    if (opcode & 0xf000) == {
        case 0x0000; if opcode == {
            case 0x00e0;
                // 00E0 - CLS
                // Clear the display.
                for x: 0..chip8.display.count-1 {
                    for y: 0..chip8.display[x].count-1 {
                        chip8.display[x][y] = 0;
                    }
                }
                chip8.pc += 2;
                return true;

            case 0x00ee;
                // 00EE - RET
                // Return from a subroutine.
                // The interpreter sets the program counter to the address at the top of the stack, then subtracts 1 from the stack pointer.
                chip8.sp -= 1;
                chip8.pc = chip8.stack[chip8.sp];
                chip8.pc += 2;
                return true;

            case;
                // all 0x0xxx should be already complete
                log_error("Unknown opcode: %\n",  formatInt(opcode, base=16, minimum_digits=4));
            }

        case 0x1000;
            // 1nnn - JP addr
            // Jump to location nnn.
            // The interpreter sets the program counter to nnn.
            nnn := opcode & 0x0fff;
            chip8.pc = nnn;
            return true;

        case 0x2000;
            // 2nnn - CALL addr
            // Call subroutine at nnn.
            // The interpreter increments the stack pointer, then puts the current PC on the top of the stack. The PC is then set to nnn.
            chip8.stack[chip8.sp] = chip8.pc;
            chip8.sp += 1;
            chip8.pc = opcode & 0x0fff;
            return true;

        case 0x3000;
            // 3xkk - SE Vx, byte
            // Skip next instruction if Vx = kk.
            // The interpreter compares register Vx to kk, and if they are equal, increments the program counter by 2.
            x := (opcode & 0x0f00) >> 8;
            kk := opcode & 0x00ff;
            if chip8.v[x] == kk then chip8.pc += 2;
            chip8.pc += 2;
            return true;

        case 0x4000;
            // 4xkk - SNE Vx, byte
            // Skip next instruction if Vx != kk.
            // The interpreter compares register Vx to kk, and if they are not equal, increments the program counter by 2.
            x := (opcode & 0x0f00) >> 8;
            kk := opcode & 0x00ff;
            if chip8.v[x] != kk then chip8.pc += 2;
            chip8.pc += 2;
            return true;

        case 0x6000;
            // 6xkk - LD Vx, byte
            // Set Vx = kk.
            // The interpreter puts the value kk into register Vx.
            x := (opcode & 0x0f00) >> 8;
            kk := opcode & 0x00ff;
            chip8.v[x] = cast(u8) kk;
            chip8.pc += 2;
            return true;

        case 0x7000;
            // 7xkk - ADD Vx, byte
            // Set Vx = Vx + kk.
            // Adds the value kk to the value of register Vx, then stores the result in Vx.
            x := (opcode & 0x0f00) >> 8;
            kk := opcode & 0x00ff;
            chip8.v[x] += cast(u8) kk;
            chip8.pc += 2;
            return true;

        case 0x8000; if (opcode & 0x000f) == {
            case 0x0000;
                // 8xy0 - LD Vx, Vy
                // Set Vx = Vy.
                // Stores the value of register Vy in register Vx.
                x := (opcode & 0x0f00) >> 8;
                y := (opcode & 0x00f0) >> 4;

                chip8.v[x] = chip8.v[y];
                chip8.pc += 2;
                return true;

            case 0x0002;
                // 8xy2 - AND Vx, Vy
                // Set Vx = Vx AND Vy.
                // Performs a bitwise AND on the values of Vx and Vy, then stores the result in Vx. A bitwise AND compares the corrseponding bits from two values, and if both bits are 1, then the same bit in the result is also 1. Otherwise, it is 0.
                x := (opcode & 0x0f00) >> 8;
                y := (opcode & 0x00f0) >> 4;
                chip8.v[x] &= chip8.v[y];
                chip8.pc += 2;
                return true;

            case 0x0003;
                // 8xy3 - XOR Vx, Vy
                // Set Vx = Vx XOR Vy.
                // Performs a bitwise exclusive OR on the values of Vx and Vy, then stores the result in Vx. An exclusive OR compares the corrseponding bits from two values, and if the bits are not both the same, then the corresponding bit in the result is set to 1. Otherwise, it is 0.
                x := (opcode & 0x0f00) >> 8;
                y := (opcode & 0x00f0) >> 4;
                chip8.v[x] ^= chip8.v[y];
                chip8.pc += 2;
                return true;

            case 0x0004;
                // 8xy4 - ADD Vx, Vy
                // Set Vx = Vx + Vy, set VF = carry.
                // The values of Vx and Vy are added together. If the result is greater than 8 bits (i.e., > 255,) VF is set to 1, otherwise 0. Only the lowest 8 bits of the result are kept, and stored in Vx.
                 x := (opcode & 0x0f00) >> 8;
                 y := (opcode & 0x00f0) >> 4;
                 sum := chip8.v[x] + chip8.v[y];

                 if sum > 255 {
                     chip8.v[0xf] = 1;
                 }

                 chip8.v[x] = sum & 0x00ff;
                 chip8.pc += 2;
                 return true;

            case 0x0005;
                // 8xy5 - SUB Vx, Vy
                // Set Vx = Vx - Vy, set VF = NOT borrow.
                // If Vx > Vy, then VF is set to 1, otherwise 0. Then Vy is subtracted from Vx, and the results stored in Vx.
                x := (opcode & 0x0f00) >> 8;
                y := (opcode & 0x00f0) >> 4;

                if chip8.v[x] > chip8.v[y] {
                    chip8.v[0xf] = 1;
                }

                chip8.v[x] -= chip8.v[y];

                chip8.pc += 2;
                return true;


            case 0x0006;
                // 8xy6 - SHR Vx {, Vy}
                // Set Vx = Vx SHR 1.
                // If the least-significant bit of Vx is 1, then VF is set to 1, otherwise 0. Then Vx is divided by 2.
                x := (opcode & 0x0f00) >> 8;
                chip8.v[0xf] = chip8.v[x] & 1;
                chip8.v[x] /= 2;
                chip8.pc += 2;
                return true;

            case;
                log("Unhandled opcode: %\n", formatInt(opcode, base=16, minimum_digits=4));
        }

        case 0xa000;
            // Annn - LD I, addr
            // Set I = nnn.
            // The value of register I is set to nnn.
            chip8.i = opcode & 0x0fff;
            chip8.pc += 2;
            return true;

        case 0xd000;
            // Dxyn - DRW Vx, Vy, nibble
            // Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision.
            // The interpreter reads n bytes from memory, starting at the address stored in I. These bytes are then displayed as sprites on screen at coordinates (Vx, Vy). Sprites are XORed onto the existing screen. If this causes any pixels to be erased, VF is set to 1, otherwise it is set to 0. If the sprite is positioned so part of it is outside the coordinates of the display, it wraps around to the opposite side of the screen.
            // See instruction 8xy3 for more information on XOR.
            // Note:
            //  - width: 8 cells (1 byte)
            //  - height: n
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
            chip8.pc += 2;
            return true;

        case 0xe000; if (opcode & 0x00ff) == {
            case 0x009e;
                // Ex9E - SKP Vx
                // Skip next instruction if key with the value of Vx is pressed.
                // Checks the keyboard, and if the key corresponding to the value of Vx is currently in the down position, PC is increased by 2.
                x := (opcode & 0x0f00) >> 8;
                key := chip8.v[x];
                chip8.pc += 2;

                if chip8.keyboard[key] == 1 {
                    chip8.pc += 2;
                }
                return true;

            case 0x00a1;
                // ExA1 - SKNP Vx
                // Skip next instruction if key with the value of Vx is not pressed.
                // Checks the keyboard, and if the key corresponding to the value of Vx is currently in the up position, PC is increased by 2.
                x := (opcode & 0x0f00) >> 8;
                key := chip8.v[x];
                chip8.pc += 2;

                if chip8.keyboard[key] == 0 {
                    chip8.pc += 2;
                }
                return true;
            case;
                log("Unhandled opcode: %\n", formatInt(opcode, base=16, minimum_digits=4));
        }



        case 0xf000; if (opcode & 0x00ff) == {
                case 0x007;
                    // Fx07 - LD Vx, DT
                    // Set Vx = delay timer value.
                    // The value of DT is placed into Vx.
                    x := (opcode & 0x0f00) >> 8;
                    chip8.v[x] = chip8.tr;
                    chip8.pc += 2;
                    return true;

                case 0x00a;
                    // Fx0A - LD Vx, K
                    // Wait for a key press, store the value of the key in Vx.
                    // All execution stops until a key is pressed, then the value of that key is stored in Vx.
                    x := (opcode & 0x0f00) >> 8;
                    if chip8.keyboard[chip8.v[x]] == 1 {
                        chip8.pc += 2;
                    }

                    return true;

                case 0x0015;
                    // Fx15 - LD DT, Vx
                    // Set delay timer = Vx.
                    // DT is set equal to the value of Vx.
                    x := (opcode & 0x0f00) >> 8;
                    chip8.tr = chip8.v[x];
                    chip8.pc += 2;
                    return true;

                case 0x0018;
                    // Fx18 - LD ST, Vx
                    // Set sound timer = Vx.
                    // ST is set equal to the value of Vx.
                    chip8.pc += 2;
                    log_error("[todo] handle Fx18\n");
                    return true;

                case 0x001e;
                    // Fx1E - ADD I, Vx
                    // Set I = I + Vx.
                    // The values of I and Vx are added, and the results are stored in I
                    x := (opcode & 0x0f00) >> 8;
                    chip8.i += chip8.v[x];
                    chip8.pc += 2;
                    return true;

                case 0x0065;
                    // Fx65 - LD Vx, [I]
                    // Read registers V0 through Vx from memory starting at location I.
                    // The interpreter reads values from memory starting at location I into registers V0 through Vx.
                    x := (opcode & 0x0f00) >> 8;
                    i := 0;
                    while (i <= x) {
                        defer i += 1;
                        chip8.v[i] = chip8.memory[chip8.i + i];
                    }

                    chip8.pc += 2;
                    return true;

                case;
                    log_error("Unhandled opcode: %\n",  formatInt(opcode, base=16, minimum_digits=4));
            }

        case;
            log_error("Unhandled opcode: %\n",  formatInt(opcode, base=16, minimum_digits=4));
    }

    print("unhandled opcode?: %\n",  formatInt(opcode, base=16, minimum_digits=4));
    return false;
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

    event_handled := true; // debug purposes
    running := true;
    last_ticks: u32;
    while (running) {
        last_ticks = SDL_GetTicks();

        // debug: we stop execution processor execution, but still see the window
        // until we manually close it
        // 16 opcodes executed per frame
        for 0..15 {
            if event_handled {
                event_handled = chip8_next_instruction(*chip8);
            }
        }

        event: SDL_Event;
        while SDL_PollEvent(*event) {
            if event.type == {
                case SDL_QUIT; running = false;
            }
        }

        keyboard_state := SDL_GetKeyboardState(null);
        chip8.keyboard[0] = keyboard_state[SDL_SCANCODE_7];
        chip8.keyboard[1] = keyboard_state[SDL_SCANCODE_8];
        chip8.keyboard[2] = keyboard_state[SDL_SCANCODE_9];
        chip8.keyboard[3] = keyboard_state[SDL_SCANCODE_0];
        chip8.keyboard[4] = keyboard_state[SDL_SCANCODE_U];
        chip8.keyboard[5] = keyboard_state[SDL_SCANCODE_I];
        chip8.keyboard[6] = keyboard_state[SDL_SCANCODE_O];
        chip8.keyboard[7] = keyboard_state[SDL_SCANCODE_P];
        chip8.keyboard[8] = keyboard_state[SDL_SCANCODE_J];
        chip8.keyboard[9] = keyboard_state[SDL_SCANCODE_K];
        chip8.keyboard[10] = keyboard_state[SDL_SCANCODE_L];
        chip8.keyboard[11] = keyboard_state[SDL_SCANCODE_SEMICOLON];
        chip8.keyboard[12] = keyboard_state[SDL_SCANCODE_M];
        chip8.keyboard[13] = keyboard_state[SDL_SCANCODE_COMMA];
        chip8.keyboard[14] = keyboard_state[SDL_SCANCODE_PERIOD];
        chip8.keyboard[15] = keyboard_state[SDL_SCANCODE_NONUSBACKSLASH];



        // render chip display
        // SDL_RenderClear(r);
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

        // todo: 60 fps (16ms => 60hz)
        render_time : u32 = SDL_GetTicks() - last_ticks;
        if render_time < 16 {
            SDL_Delay(16 - render_time);
            if chip8.tr > 0 then chip8.tr -= 1;
        } else {
            SDL_Delay(1);
        }
    }
}
