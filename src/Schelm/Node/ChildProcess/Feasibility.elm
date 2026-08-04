module Schelm.Node.ChildProcess.Feasibility exposing (Process, Exit, spawn, readStdout, readStderr, wait, terminate)

{-| Pull-based feasibility fixture; not the proposed final API.

@docs Process, Exit, spawn, readStdout, readStderr, wait, terminate
-}

import Bytes exposing (Bytes)
import Elm.Kernel.SchelmChildProcess
import Task exposing (Task)


{-| Opaque live process handle. -}
type Process
    = Process


{-| Terminal process data. Empty signal means normal exit; `code = -1` means no numeric exit code. -}
type alias Exit =
    { code : Int
    , signal : String
    }


{-| Spawn and resolve only after Node's `spawn` event; fail on `error`. -}
spawn : String -> List String -> Task String Process
spawn =
    Elm.Kernel.SchelmChildProcess.spawn


{-| Read one stdout chunk, or `Nothing` after stream end. -}
readStdout : Process -> Task String (Maybe Bytes)
readStdout =
    Elm.Kernel.SchelmChildProcess.readStdout


{-| Read one stderr chunk, or `Nothing` after stream end. -}
readStderr : Process -> Task String (Maybe Bytes)
readStderr =
    Elm.Kernel.SchelmChildProcess.readStderr


{-| Wait for the one cached terminal result. -}
wait : Process -> Task Never Exit
wait process =
    Elm.Kernel.SchelmChildProcess.wait process
        |> Task.map (\( code, signal ) -> fromKernelExit code signal)


{-| Send TERM to the owned process group in this feasibility fixture. -}
terminate : Process -> Task Never ()
terminate =
    Elm.Kernel.SchelmChildProcess.terminate


fromKernelExit : Int -> String -> Exit
fromKernelExit code signal =
    { code = code, signal = signal }
