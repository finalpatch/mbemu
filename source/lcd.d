module mbemu.lcd;
import mbemu.mem;
import mbemu.fpga;
import std.bitmanip;

version(WithLCD)
{
	import derelict.sdl2.sdl;
	static this()
	{
		DerelictSDL2.load();
		SDL_Init(SDL_INIT_VIDEO);
	}
}

class LCD
{
public:
	this(SDRAM sdram)
	{
		m_sdram = sdram;
		init();
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
	final void handleEvents()
	{
		version(WithLCD)
		{
			SDL_Event event;
			if (SDL_PollEvent(&event))
			{
				switch (event.type)
				{
				case SDL_QUIT:
					import std.c.stdlib;
					exit(0);
					break;
				default:
					break;
				}
			}
		}
	}
	
private:
	SDRAM       m_sdram;
	bool        m_enabled;
	uint        m_frameBuffer;

	version(WithLCD)
	{
		static immutable width = 320, height = 240;
		SDL_Window*   win;
		SDL_Renderer* ren;
		SDL_Texture*  tex;

		final void init()
		{
			SDL_CreateWindowAndRenderer(width, height, 0, &win, &ren);
			tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, width, height);
		}
		final void update()
		{
			if (m_enabled)
			{
				ubyte[] buf = m_sdram.getBuffer();
				ubyte* fb = buf[m_frameBuffer - m_sdram.base .. $].ptr;
				SDL_UpdateTexture(tex, cast(const(SDL_Rect)*)null, fb, width * 4);
				SDL_RenderCopy(ren, tex, null, null);
				SDL_RenderPresent(ren);
			}
			else
			{
				SDL_SetRenderDrawColor(ren, 0, 0, 0, 0xff);
				SDL_RenderFillRect(ren, null);
				SDL_RenderPresent(ren);
			}
		}
	}
	else
	{
		final void init() {}
		final void update() {}
	}
}
