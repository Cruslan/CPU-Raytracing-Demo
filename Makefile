CXX = g++
ASM = nasm
MOC = /usr/lib64/qt6/libexec/moc
QT_CFLAGS = $(shell pkg-config --cflags Qt6Widgets)
QT_LIBS = $(shell pkg-config --libs Qt6Widgets)

all: raytracer

main.moc: main.cpp raytracer.h
	$(MOC) main.cpp -o main.moc

raytracer: main.cpp raytracer.o main.moc
	$(CXX) -fPIC -std=c++17 $(QT_CFLAGS) main.cpp raytracer.o -o raytracer $(QT_LIBS)

raytracer.o: raytracer.asm
	$(ASM) -f elf64 raytracer.asm -o raytracer.o

clean:
	rm -f raytracer raytracer.o main.moc
