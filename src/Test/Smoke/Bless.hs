{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Smoke.Bless
  ( blessResults
  ) where

import Control.Exception (catch, throwIO)
import Control.Monad (forM)
import qualified Data.Vector as Vector
import Test.Smoke.Files
import Test.Smoke.Types

blessResults :: Results -> IO Results
blessResults results =
  forM results $ \case
    result@SuiteResultError {} -> return result
    SuiteResult suiteName location testResults -> do
      blessedResults <- forM testResults (blessResult location)
      return $ SuiteResult suiteName location blessedResults

blessResult :: Path -> TestResult -> IO TestResult
blessResult location (TestResult test (TestFailure _ status stdOut stdErr))
  | isFailureWithMultipleExpectedValues status =
    return $
    TestResult test $
    TestError (BlessError (CouldNotBlessWithMultipleValues "status"))
  | isFailureWithMultipleExpectedValues stdOut =
    return $
    TestResult test $
    TestError (BlessError (CouldNotBlessWithMultipleValues "stdout"))
  | isFailureWithMultipleExpectedValues stdErr =
    return $
    TestResult test $
    TestError (BlessError (CouldNotBlessWithMultipleValues "stderr"))
  | otherwise =
    do case status of
         PartFailure comparisons ->
           writeFixture
             location
             (testStatus test)
             (snd (Vector.head comparisons))
         _ -> return ()
       case stdOut of
         PartFailure comparisons ->
           writeFixtures
             location
             (testStdOut test)
             (snd (Vector.head comparisons))
         _ -> return ()
       case stdErr of
         PartFailure comparisons ->
           writeFixtures
             location
             (testStdErr test)
             (snd (Vector.head comparisons))
         _ -> return ()
       return $ TestResult test TestSuccess
     `catch` (\(e :: SmokeBlessError) ->
                return (TestResult test $ TestError $ BlessError e)) `catch`
    (return . TestResult test . TestError . BlessError . BlessIOException)
  where
    isFailureWithMultipleExpectedValues (PartFailure comparisons) =
      Vector.length comparisons > 1
    isFailureWithMultipleExpectedValues _ = False
blessResult _ result = return result

writeFixture :: FixtureType a => Path -> Fixture a -> a -> IO ()
writeFixture _ (Fixture contents@(Inline _) _) value =
  throwIO $
  CouldNotBlessInlineFixture (fixtureName contents) (serializeFixture value)
writeFixture location (Fixture (FileLocation path) _) value =
  writeToPath (location </> path) (serializeFixture value)

writeFixtures ::
     forall a. FixtureType a
  => Path
  -> Fixtures a
  -> a
  -> IO ()
writeFixtures location (Fixtures fixtures) value
  | Vector.length fixtures == 1 =
    writeFixture location (Vector.head fixtures) value
  | Vector.length fixtures == 0 =
    throwIO $ CouldNotBlessAMissingValue (fixtureName (undefined :: Contents a))
  | otherwise =
    throwIO $
    CouldNotBlessWithMultipleValues (fixtureName (undefined :: Contents a))
