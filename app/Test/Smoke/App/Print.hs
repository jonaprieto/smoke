{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Test.Smoke.App.Print where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT, ask)
import qualified Data.Maybe as Maybe
import Data.String (IsString(..))
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Path
import System.Console.ANSI
import System.IO (Handle, stderr, stdout)
import Test.Smoke.App.OptionTypes (AppOptions(..), ColorOutput(..))

type Output a = ReaderT AppOptions IO a

showText :: Show a => a -> Text
showText = Text.pack . show

showPath :: Path b t -> Text
showPath path = "\"" <> Text.pack (toFilePath path) <> "\""

int :: Int -> Text
int = fromString . show

hasEsc :: Text -> Bool
hasEsc = Maybe.isJust . Text.find (== '\ESC')

spaces :: Int -> Text
spaces n = Text.replicate n space

space :: Text
space = " "

newline :: Text
newline = "\n"

indented :: Int -> Text -> Text
indented n = Text.unlines . indented' . Text.lines
  where
    indented' [] = []
    indented' (first:rest) = first : map (mappend (spaces n)) rest

indentedAll :: Int -> Text -> Text
indentedAll n = Text.unlines . map (mappend (spaces n)) . Text.lines

putEmptyLn :: Output ()
putEmptyLn = liftIO $ putStrLn ""

putPlainLn :: Text -> Output ()
putPlainLn = hPutStrWithLn stdout

putGreenLn :: Text -> Output ()
putGreenLn = putColorLn Green

putRed :: Text -> Output ()
putRed = putColor Red

putRedLn :: Text -> Output ()
putRedLn = putColorLn Red

putColorLn :: Color -> Text -> Output ()
putColorLn color = withColor color (hPutStrWithLn stdout)

putColor :: Color -> Text -> Output ()
putColor color = withColor color (liftIO . TextIO.putStr)

putError :: Text -> Output ()
putError = withColor Red $ hPutStrWithLn stderr

hPutStrWithLn :: Handle -> Text -> Output ()
hPutStrWithLn handle contents = do
  liftIO $ TextIO.hPutStr handle contents
  unless (newline `Text.isSuffixOf` contents) $
    liftIO $ TextIO.hPutStrLn handle ""

withColor :: Color -> (Text -> Output ()) -> Text -> Output ()
withColor color act contents = do
  options <- ask
  if optionsColor options == Color && not (hasEsc contents)
    then do
      liftIO $ setSGR [SetColor Foreground Dull color]
      act contents
      liftIO $ setSGR [Reset]
    else act contents
