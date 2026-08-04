port module BuilderMain exposing (main)
import Platform
import Schelm.Node.ChildProcess as Child
port report : String -> Cmd msg
main : Program () () Never
main = Platform.worker { init = \_ -> ( (), report (if checks then "ok" else "failed") ), update = \msg model -> never msg, subscriptions = \_ -> Sub.none }
checks =
    Child.program "" == Err Child.EmptyProgram
        && Child.argument "a\u{0000}b" == Err (Child.ContainsNul "argument")
        && Child.byteLimit -1 == Nothing
        && Child.milliseconds -1 == Nothing
        && Child.byteLimit 0 /= Nothing
