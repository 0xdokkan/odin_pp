package main
import "core:os"
import application "application"
main :: proc() { application.start(os.args[1:]) }
