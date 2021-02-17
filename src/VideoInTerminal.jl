module VideoInTerminal

using ImageCore, ImageInTerminal, TestImages, VideoIO

import ImageInTerminal: TermColor256, encodeimg, SmallBlocks, use_256, use_24bit

export testvideo, play, use_256, use_24bit

ansi_moveup(n::Int) = string("\e[", n, "A")
ansi_movecol1 = "\e[1G"
ansi_cleartoend = "\e[0J"
ansi_enablecursor = "\e[?25h"
ansi_disablecursor = "\e[?25l"


function testvideo(io::IO, name::String="annie_oakley"; fps::Real=30, maxsize::Tuple = displaysize(io))
    io = VideoIO.testvideo(name)
    f = VideoIO.openvideo(io)
    t = 1
    rows = 1
    img = read(f)
    img_w, img_h = size(img)
    io_h, io_w = maxsize
    blocks = 3img_w <= io_w ? BigBlocks() : SmallBlocks()
    c = ImageInTerminal.colormode[]
    println(summary(img))
    seekstart(f)
    tim = Timer(0, interval=1/fps)
    frame = 1
    print(ansi_disablecursor)
    try
        for img in f
            t = @elapsed begin
                str = sprint() do ios
                    lines, rows, cols = encodeimg(blocks, c, img, io_h, io_w)
                    for line in lines
                        println(ios, line)
                    end
                    actual_fps = 1 / t
                    println(ios, "FPS: $(round(actual_fps, digits=1)). Frame: $frame")
                end
                frame == 1 ? print(str) : print(ansi_moveup(rows+1), ansi_movecol1, str)
                wait(tim)
            end
            frame += 1
        end
    finally
        print(ansi_enablecursor)
        close(f)
    end
end
testvideo(name::String="annie_oakley"; kwargs...) = testvideo(stdout, name; kwargs...)


function play(io::IO, framestack::Vector{Matrix{T}}; fps::Real=30, maxsize::Tuple = displaysize(io)) where {T<:Colorant}
    img_w, img_h = size(framestack[1])
    io_h, io_w = maxsize
    blocks = 3img_w <= io_w ? BigBlocks() : SmallBlocks()
    c = ImageInTerminal.colormode[]
    t = 1
    rows = 1
    println(summary(framestack[1]))
    frame = 1
    nframes = length(framestack)
    print(ansi_disablecursor)
    try
        for i in 1:nframes
            t = @elapsed begin
                tim = Timer(1/fps)
                str = sprint() do ios
                    lines, rows, cols = encodeimg(blocks, c, framestack[i], io_h, io_w)
                    for line in lines
                        println(ios, line)
                    end
                    actual_fps = 1 / t
                    println(ios, "FPS: $(round(actual_fps, digits=1)). Frame: $frame/$nframes")
                end
                frame == 1 ? print(str) : print(ansi_moveup(rows+1), ansi_movecol1, str)
                wait(tim)
            end
            frame += 1
        end
    finally
        print(ansi_enablecursor)
    end
end
play(framestack::Vector{Matrix{T}}; kwargs...) where {T<:Colorant} = play(stdout, framestack; kwargs...)

end # module