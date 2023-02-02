"""
    VideoInTerminal

Video playback in the terminal via. ImageInTerminal and VideoIO

- `play(arrray, dim)` to play through `array` along dimension `dim`
- `play(framestack)` where `framestack` is a vector of image arrays
- `play(fpath::String)` where fpath is a path to a video file
- `explore(...)` like `play` but starts paused
- `showcam()` to stream the primary system camera
- `testvideo(name)` to show a VideoIO test video, such as "annie_oakley", or "ladybird"

Control keys:
- `p` or `space-bar`: pause
- `left-` or `up-arrow`: step backward (in framestack mode)
- right-` or `down-arrow`: step forward (in framestack mode)
- `ctrl-c` or `q`: exit

`ImageInTerminal` core controls are accessible:
- `VideoInTerminal.use_24bit()` force using 24-bit color
- `VideoInTerminal.use_256()` force using 256 colors
"""
module VideoInTerminal

using ImageCore, ImageInTerminal, VideoIO

import ImageInTerminal: TermColor256, encodeimg, SmallBlocks, BigBlocks, use_256, use_24bit

export play, showcam, testvideo, explore, use_256, use_24bit

ansi_moveup(n::Int) = string("\e[", n, "A")
ansi_movecol1 = "\e[1G"
ansi_cleartoend = "\e[0J"
ansi_enablecursor = "\e[?25h"
ansi_disablecursor = "\e[?25l"

setraw!(io, raw) = ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid},Int32), io.handle, raw)

"""
    testvideo(io::IO, name::String; kwargs...)
    testvideo(name::String=; kwargs...)

Display a VideoIO named test video.

Control keys:
- `p` or `space-bar`: pause
- `ctrl-c` or `q`: exit

kwargs:
- `fps::Real=30`
- `maxsize::Tuple = displaysize(io)`
"""
function testvideo(io::IO, name::String; kwargs...)
    vio = VideoIO.testvideo(name)
    play(io, VideoIO.openvideo(vio); kwargs...)
end
testvideo(name::String; kwargs...) = testvideo(stdout, name; kwargs...)

"""
    showcam(io::IO=stdout; kwargs...)

Display system camera. Defaults to first from the list that FFMPEG populates.
i.e. `VideoInTerminal.VideoIO.CAMERA_DEVICES`

Control keys:
- `p` or `space-bar`: pause
- `ctrl-c` or `q`: exit

kwargs:
- `maxsize::Tuple = displaysize(io)`
- `device=VideoIO.DEFAULT_CAMERA_DEVICE[]`
- `format=VideoIO.DEFAULT_CAMERA_FORMAT[]`
- `options=VideoIO.DEFAULT_CAMERA_OPTIONS`
"""
function showcam(io::IO=stdout;
    device=nothing,
    format=nothing,
    options=nothing,
    max_loops = 2,
    kwargs...)
    if device === nothing || format === nothing || options === nothing
        VideoIO.init_camera_devices()
        VideoIO.init_camera_settings()
        isnothing(device) && (device = VideoIO.DEFAULT_CAMERA_DEVICE[])
        isnothing(format) && (format = VideoIO.DEFAULT_CAMERA_FORMAT[])
        isnothing(options) && (options = VideoIO.DEFAULT_CAMERA_OPTIONS)
    end
    cam = VideoIO.opencamera(device, format, options)
    play(io, cam; fps=30, stream=true, max_loops=max_loops, kwargs...)
end

"""
    play(v; kwargs...)
    play(io::IO, fpath::String; kwargs...)
    play(io::IO, vreader::T; kwargs...) where {T<:VideoIO.VideoReader}
    play(io::IO, framestack::Vector{T}; kwargs...) where {T<:AbstractArray}

Play a video at a filepath, a VideoIO.VideoReader object, or a framestack with a Colorant element type.

Framestacks should be vectors of images with a Colorant element type.

Control keys:
- `p` or `space-bar`: pause
- `left-` or `up-arrow`: step backward (in framestack mode)
- `right-` or `down-arrow`: step forward (in framestack mode)
- `ctrl-c` or `q`: exit

kwargs:
- `fps::Real=30`
- `maxsize::Tuple = displaysize(io)`
- `stream::Bool=false` if true, don't terminate immediately if eof is reached
"""
play(v; kwargs...) = play(stdout, v; kwargs...)
play(io::IO, fpath::String; kwargs...) = play(io, VideoIO.openvideo(fpath); kwargs...)
function play(io::IO, vreader::T; fps::Real=30, maxsize::Tuple = displaysize(io), stream::Bool=false, paused = false, max_loops = 1) where {T<:VideoIO.VideoReader}
    # sizing
    img = read(vreader)
    try
        seekstart(vreader)
    catch
    end
    img_w, img_h = size(img)
    io_h, io_w = maxsize
    blocks = 3img_w <= io_w ? BigBlocks() : SmallBlocks()

    # fixed
    c = ImageInTerminal.colormode[]

    # vars
    frame = 1
    finished = false
    first_print = true
    actual_fps = 0
    img_shown = false

    println(summary(img))
    keytask = @async begin
        try
            setraw!(stdin, true)
            while !finished
                keyin = read(stdin, Char)
                keyin in ['p',' '] && (paused = !paused)
                keyin in ['\x03','q'] && (finished = true)
            end
        catch
        finally
            setraw!(stdin, false)
        end
    end
    try
        print(ansi_disablecursor)
        while !finished
            tim = Timer(1/fps)
            t = @elapsed begin
                if paused
                    wait(tim)
                    continue
                end
                nloops = 0
                while nloops < max_loops && !eof(vreader)
                    VideoIO.read!(vreader, img)
                    img_shown = false
                    nloops += 1
                end
                if img_shown
                    wait(tim)
                    continue
                end
                lines, rows, cols = encodeimg(blocks, c, img, io_h, io_w)
                str = sprint() do ios
                    println.((ios,), lines)
                    println(ios, "ctrl-c to exit. Preview: $(cols)x$(rows) FPS: $(round(actual_fps, digits=1)). Frame: $frame")
                end
                frame == 1 ? print(str) : print(ansi_moveup(rows+1), ansi_movecol1, str)
                first_print = false
                (!stream && !paused && eof(vreader)) && break
                !paused && (frame += 1)
                img_shown = true
                wait(tim)
            end
            actual_fps = 1 / t
        end
    catch e
        isa(e,InterruptException) || rethrow()
    finally
        print(ansi_enablecursor)
        finished = true
        @async Base.throwto(keytask, InterruptException())
        close(vreader)
        wait(keytask)
    end
    return
end
play(io::IO, framestack::Vector{T}; kwargs...) where {T<:AbstractArray} = play(io, framestack, 1; kwargs...)

function play(io::IO, arr::T, dim::Int; fps::Real=30, maxsize::Tuple = displaysize(io), paused = false) where {T<:AbstractArray}
    @assert dim <= ndims(arr) "Requested dimension $dim, but source array only has $(ndims(arr)) dimensions"
    @assert ndims(arr) <= 3 "Source array dimensions cannot exceed 3"
    firstframe = T <: Vector ? first(selectdim(arr, dim, 1)) : selectdim(arr, dim, 1)
    @assert eltype(firstframe) <: Colorant "Element type $(eltype(firstframe)) not supported"
    # sizing
    img_w, img_h = size(firstframe)
    io_h, io_w = maxsize
    blocks = 3img_w <= io_w ? BigBlocks() : SmallBlocks()

    # fixed
    nframes = size(arr, dim)
    c = ImageInTerminal.colormode[]

    # vars
    frame = 1
    finished = false
    first_print = true
    actual_fps = 0

    println(summary(firstframe))
    keytask = @async begin
        try
            setraw!(stdin, true)
            while !finished
                keyin = read(stdin, Char)
                if UInt8(keyin) == 27
                    keyin = read(stdin, Char)
                    if UInt8(keyin) == 91
                        keyin = read(stdin, Char)
                        UInt8(keyin) in [68,65] && (frame = frame <= 1 ? 1 : frame - 1) # left & up arrows
                        UInt8(keyin) in [67,66] && (frame = frame >= nframes ? nframes : frame + 1) # right & down arrows
                    end
                end
                keyin in ['p',' '] && (paused = !paused)
                keyin in ['\x03','q'] && (finished = true)
            end
        catch
        finally
            setraw!(stdin, false)
        end
    end
    try
        print(ansi_disablecursor)
        setraw!(stdin, true)
        while !finished
            tim = Timer(1/fps)
            t = @elapsed begin
                img = T <: Vector ? collect(first(selectdim(arr, dim, frame))) : selectdim(arr, dim, frame)
                lines, rows, cols = encodeimg(blocks, c, img, io_h, io_w)
                str = sprint() do ios
                    println.((ios,), lines)
                    if paused
                        println(ios, "Preview: $(cols)x$(rows) Frame: $frame/$nframes", " "^15)
                    else
                        println(ios, "Preview: $(cols)x$(rows) Frame: $frame/$nframes FPS: $(round(actual_fps, digits=1))", " "^5)
                    end
                end
                first_print ? print(str) : print(ansi_moveup(rows+1), ansi_movecol1, str)
                first_print = false
                (!paused && frame == nframes) && break
                !paused && (frame += 1)
                wait(tim)
            end
            actual_fps = 1 / t
        end
    catch e
        isa(e,InterruptException) || rethrow()
    finally
        print(ansi_enablecursor)
        finished = true
        @async Base.throwto(keytask, InterruptException())
        wait(keytask)
    end
    return
end
play(arr::T, dim::Int; kwargs...) where {T<:AbstractArray} = play(stdout, arr, dim; kwargs...)

"""
    explore(io::IO, arr::T, dim::Int; kwargs...) where {T<:AbstractArray}
    explore(arr::T, dim::Int; kwargs...) where {T<:AbstractArray}
    explore(io::IO, framestack::Vector{T}; kwargs...) where {T<:AbstractArray}
    explore(framestack::Vector{T}; kwargs...) where {T<:AbstractArray}

Like `play`, but starts paused
"""
explore(io::IO, arr::T, dim::Int; kwargs...) where {T<:AbstractArray} = play(io, arr, dim; paused=true, kwargs...)
explore(arr::T, dim::Int; kwargs...) where {T<:AbstractArray} = play(stdout, arr, dim; paused=true, kwargs...)
explore(io::IO, framestack::Vector{T}; kwargs...) where {T<:AbstractArray} = explore(io, framestack, 1; kwargs...)
explore(framestack::Vector{T}; kwargs...) where {T<:AbstractArray} = explore(stdout, framestack, 1; kwargs...)

end # module
