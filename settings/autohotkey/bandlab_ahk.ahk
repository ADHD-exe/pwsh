#Requires AutoHotkey v2.0

HoldKey(key)
{
    SendEvent "{" key " down}"
    KeyWait key
    SendEvent "{" key " up}"
}

; Alphabet keys
$*a::HoldKey("a")
$*b::HoldKey("b")
$*c::HoldKey("c")
$*d::HoldKey("d")
$*e::HoldKey("e")
$*f::HoldKey("f")
$*g::HoldKey("g")
$*h::HoldKey("h")
$*i::HoldKey("i")
$*j::HoldKey("j")
$*k::HoldKey("k")
$*l::HoldKey("l")
$*m::HoldKey("m")
$*n::HoldKey("n")
$*o::HoldKey("o")
$*p::HoldKey("p")
$*q::HoldKey("q")
$*r::HoldKey("r")
$*s::HoldKey("s")
$*t::HoldKey("t")
$*u::HoldKey("u")
$*v::HoldKey("v")
$*w::HoldKey("w")
$*x::HoldKey("x")
$*y::HoldKey("y")
$*z::HoldKey("z")

; Number keys
$*1::HoldKey("1")
$*2::HoldKey("2")
$*3::HoldKey("3")
$*4::HoldKey("4")
$*5::HoldKey("5")
$*6::HoldKey("6")
$*7::HoldKey("7")
$*8::HoldKey("8")
$*9::HoldKey("9")
$*0::HoldKey("0")
