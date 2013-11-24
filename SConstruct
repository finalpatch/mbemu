import os
env = Environment(
    tools = ['gcc', 'g++', 'ar', 'as', 'gnulink'],
    ENV   = {'PATH' : os.environ['PATH']},
    CC    = 'mb-gcc',
    CXX   = 'mb-g++',
    AS    = 'mb-as',
    AR    = 'mb-ar',
    CCFLAGS = '-mxl-barrel-shift -mxl-pattern-compare -mcpu=v8.20.a -mno-xl-soft-mul -mbig-endian -fno-strict-aliasing -fno-exceptions',
    LINKFLAGS = '-Wl,-defsym,_STACK_SIZE=4096 -Wl,-defsym,_HEAP_SIZE=8192')
env.Program('test.elf', 'test.cpp')
