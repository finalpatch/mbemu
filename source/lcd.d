module mbemu.lcd;
import mbemu.mem;
import mbemu.fpga;
import std.bitmanip;
import core.thread;
import core.sync.mutex;
import core.sync.condition;

version(WithLCD)
{
	import derelict.sdl2.sdl;
	import derelict.opengl3.gl;
}

class LCD : Thread
{
public:
	this(SDRAM sdram, FPGA fpga)
	{
		super(&run);
		m_sdram = sdram;
        m_fpga = fpga;
		init();
	}
	~this()
	{
		fini();
	}
	final bool enabled() { return m_enabled; }
	final void enabled(bool e)
	{
		m_enabled = e;
		update();
	}
	final uint frameBuffer() { return m_frameBuffer; }
	final void frameBuffer(uint fb)
	{
		m_frameBuffer = fb;
		update();
	}
	final bool handleEvents()
	{
		version(WithLCD)
		{
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
                        default: break;
                        }
                        if (k >= 0)
                        {
                            if (event.type == SDL_KEYDOWN)
                                m_fpga.reg[FPGA.ButtonStatus] |= (1 << k);
                            else
                                m_fpga.reg[FPGA.ButtonStatus] &= ~(1 << k);
                            m_fpga.reg[FPGA.InterruptStatus] |= m_fpga.reg[FPGA.InterruptControl] & (1 << FPGA.ButtonInterrupt);
                        }
                    }
                    break;
				case SDL_QUIT:
					keepRunning = false;
					cond.notify();
					join();
					return false;
				default:
					break;
				}
			}
		}
		return true;
	}
	
	uint[256] lut;
	
private:
	SDRAM m_sdram;
    FPGA m_fpga;
	shared bool m_enabled;
	shared uint m_frameBuffer;

	version(WithLCD)
	{
		static immutable width = 320, height = 240;
		SDL_Window*   win;
		SDL_GLContext glrc;
		GLuint        tex;
		uint[]        buf;
		Condition     cond;
		shared bool   keepRunning = true;

		final void init()
		{
            buf = new uint[width * height];
			DerelictSDL2.load();
			DerelictGL.load();
			SDL_Init(SDL_INIT_VIDEO);
			win = SDL_CreateWindow("mbemu", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, width*2, height*2, SDL_WINDOW_OPENGL);
			glrc = SDL_GL_CreateContext(win);
			DerelictGL.reload();
			SDL_GL_SetSwapInterval(0);
			glLoadIdentity();
			glGenTextures(1, &tex);
			glEnable(GL_TEXTURE_RECTANGLE);
			glBindTexture(GL_TEXTURE_RECTANGLE, tex);
			SDL_GL_MakeCurrent(win, null);
			cond = new Condition(new Mutex());
			start();		// start the rendering thread (void run())
		}
		final void fini()
		{
			SDL_GL_DeleteContext(glrc);
			SDL_DestroyWindow(win);
			SDL_Quit();
		}
		final void run()
		{
			while(keepRunning)
			{
				synchronized (cond.mutex)
					cond.wait();
				update_i();
			}
		}
		final void update()
		{
			synchronized (cond.mutex)
				cond.notify();
		}
		final void update_i()
		{
			SDL_GL_MakeCurrent(win, glrc);
			if (m_enabled)
			{
				ubyte[] fb =  m_sdram.getBuffer!ubyte()[m_frameBuffer - m_sdram.base .. m_frameBuffer - m_sdram.base + 256];
				uint* pixels; int pitch;
				for(uint row = 0; row < height; ++row)
				{
					for(uint col = 0; col < width; ++col)
						buf[row * width + col] = lut[fb[row * width + col]];
				}
				glTexImage2D(GL_TEXTURE_RECTANGLE, 0, GL_RGBA, width, height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, buf.ptr);
                glBegin(GL_QUADS);
                    glTexCoord2i(0, 0);           glVertex2f(-1.0f,  1.0f);
                    glTexCoord2i(0, height);      glVertex2f(-1.0f, -1.0f);
                    glTexCoord2i(width, height);  glVertex2f( 1.0f, -1.0f);
                    glTexCoord2i(width, 0);       glVertex2f( 1.0f,  1.0f);
				glEnd();
			}
			else
			{
				glClearColor(0,0,0,1);
				glClear(GL_COLOR_BUFFER_BIT);
			}
			SDL_GL_SwapWindow(win);
		}
	}
	else
	{
		final void init() {}
		final void fini() {}
		final void update() {}
		final void run() {}
	}
}
