module Main where

import LoadImage
import Shifts
import FileList
import System.Directory ( removeFile )

{--Error handling--}
import Control.Exception ( catch
                         , SomeException
                         )
{--State variables--}
import Data.IORef

{--GTK bindings--}
import Graphics.UI.Gtk
import Graphics.UI.Gtk.Gdk.PixbufAnimation
import System.Glib.UTFString

{--Needed for event handlers--}
import Control.Monad.IO.Class ( liftIO )

{--Concurrency--}
import Control.Concurrent ( forkIO
                          , ThreadId
                          , killThread
                          )
{--System buffer, for yanking filename--}
import System.Hclip

{- Portable filepath handling -}
import qualified  Filesystem.Path as FS
import qualified  Filesystem.Path.CurrentOS as FS.OS

{- Little things -}
import Data.Maybe
import Data.List ( findIndex )
import Data.Text ( unpack
                 , pack
                 , Text
                 )

-- TODO:
-- Zooms needed*:
--  fit,
--  fill,
--  width+vscroll (maybe with '+' '-' and 'd' 's'),
--  free with scrollbars
-- *no zooms for animations
--
-- TODO
--  Add warning icon if file (animation) did not fit to window
--
-- TODO
--  Add "Cycle!" message on repeat
--  Need to either add counter or `watched` mask to Position, ugh
--
-- FIXME
--  Escape spaces when yanking
--
-- TODO
--  Dig into folder if it is alone in file list (initial!)

{- BEGIN Main -}
main :: IO ()
main = do
    position <- initFileList
    printSummary position
    launchGUI position

launchGUI :: IORef Position -> IO ()
launchGUI position = do
    {- Creating GUI -}
    initGUI
    window  <- windowNew
    image   <- imageNewFromIconName "image-missing" IconSizeLargeToolbar
    overlay <- overlayNew
    overlayAdd overlay image
    containerAdd window overlay
    set window [ windowTitle := "My experiment"
               , containerBorderWidth := 0 ]
    {- Event handlers -}
    -- Exit
    on window objectDestroy mainQuit
    -- Keypresses
    on window keyPressEvent $ tryEvent $ do
        e <- eventModifier
        k <- eventKeyName
        liftIO $ keyWrapper e k position image
    -- Window resize
    on window configureEvent $ liftIO $ do
        redrawImage image position
    {- Initializing GUI -}
    widgetShowAll window
    -- Load first image
    nextImage nextRan position image
    -- Main GUI thread
    mainGUI

keyWrapper :: [Modifier] -> Text -> IORef Position -> Image -> IO ()
keyWrapper modifier inputChar iorefPosition imageWidget
    |  recievedChar == "e"
    || recievedChar == "Right"
       = nextImage nextSeq iorefPosition imageWidget

    |  recievedChar == "w"
    || recievedChar == "Left" 
       = nextImage prevSeq iorefPosition imageWidget

    | recievedChar == "p" 
      = do
        fullFilePath <- extractFullName iorefPosition
        setClipboard fullFilePath
        let fileName = FS.OS.encodeString $
                       FS.filename $
                       FS.OS.decodeString fullFilePath
        putStrLn fileName

    |  recievedChar == "space"
    || recievedChar == "Return"
    || recievedChar == "Up"
       = nextImage nextRan iorefPosition imageWidget

    |  recievedChar == "BackSpace"
    || recievedChar == "Down"
       = nextImage prevRan iorefPosition imageWidget

    |  recievedChar == "q"
    || recievedChar == "Escape"
       = mainQuit

    |  recievedChar == "Delete"
       = do
         fullFilePath <- extractFullName iorefPosition
         removeFile fullFilePath
         nextImage nextSeq iorefPosition imageWidget

    |  recievedChar == "y"
       = do
         fullFilePath <- extractFullName iorefPosition
         putStrLn fullFilePath
         setClipboard fullFilePath

    |  recievedChar == "0"
       = do
         position <- readIORef iorefPosition
         writeIORef iorefPosition ( setZero position )
         nextImage nextSeq iorefPosition imageWidget

    | otherwise = return ()
  where recievedChar = unpack inputChar

setZero :: Position -> Position
setZero var @ Position { ix_shuffle = shuf }
      = var { ix_pos = -1
            , ix_rand = indexOfZero }
    where indexOfZero = fromMaybe ( error "error #4"       )
                                  ( findIndex (==(0)) shuf )

printSummary :: IORef Position -> IO ()
printSummary a = do
    f <- readIORef a
    putStrLn $  "Opening "
             ++ show ( length $ files f )
             ++ " files"
