module mbemu.input;
import mbemu.fpga;

bool handleEvents(FPGA fpga)
{
    version(WithLCD)
    {
        import derelict.sdl2.sdl;
        
        SDL_Event event;
        if (SDL_PollEvent(&event))
        {
            switch (event.type)
            {
            case SDL_KEYUP:
            case SDL_KEYDOWN:
                {
                    int k = -1;
                    switch(event.key.keysym.sym)
                    {
                    case SDLK_UP:     k = 0; break;
                    case SDLK_DOWN:   k = 1; break;
                    case SDLK_LEFT:   k = 2; break;
                    case SDLK_RIGHT:  k = 3; break;
                    case SDLK_ESCAPE: k = 4; break;
                    case SDLK_LCTRL:  k = 5; break;
                    case SDLK_LSHIFT: k = 6; break;
                    case SDLK_LALT:   k = 7; break;
                    case SDLK_RETURN: k = 8; break;
                    case SDLK_TAB:    k = 9; break;
                    default: break;
                    }
                    if (k >= 0)
                    {
                        if (event.type == SDL_KEYDOWN)
                            fpga.reg[FPGA.ButtonStatus] |= (1 << k);
                        else
                            fpga.reg[FPGA.ButtonStatus] &= ~(1 << k);
                        fpga.reg[FPGA.InterruptStatus] |= fpga.reg[FPGA.InterruptControl] & (1 << FPGA.ButtonInterrupt);
                    }
                }
                break;
            case SDL_QUIT:
                return false;
            default:
                break;
            }
        }
    }
    return true;
}
