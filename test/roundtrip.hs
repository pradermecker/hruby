module Main where

import Foreign.Ruby.Helpers(toRuby,fromRuby,freezeGC)
import Foreign.Ruby.Bindings
import Foreign.Ruby.Safe
import Data.Aeson
import Control.Monad
import Test.QuickCheck
import Test.QuickCheck.Monadic
import qualified Data.Text as T
import Data.Attoparsec.Number
import qualified Data.Vector as V

instance Arbitrary Number where
    arbitrary = frequency [ (1, fmap D arbitrary) , (1, fmap I arbitrary) ]

subvalue :: Gen Value
subvalue = frequency [(50,s),(20,b),(20,n),(1,h),(1,a)]

str :: Gen T.Text
str = fmap T.pack (listOf (elements (['A'..'Z'] ++ ['a' .. 'z'] ++ ['0'..'9'])))

s :: Gen Value
s = fmap String str

a :: Gen Value
a = fmap (Array . V.fromList) (resize 100 (listOf subvalue))

b :: Gen Value
b = fmap Bool arbitrary

n :: Gen Value
n = fmap (Number . fromIntegral) (arbitrary :: Gen Integer)

h :: Gen Value
h = fmap object $ do
        k <- listOf str
        v <- listOf subvalue
        return (zip k v)

instance Arbitrary Value where
    arbitrary = frequency [(1,s),(5,a),(1,b),(1,n),(5,h)]

roundTrip :: RubyInterpreter -> Property
roundTrip i = monadicIO $ do
    v <- pick (arbitrary :: Gen Value)
    ex <- run $ freezeGC $ do
        rub <- makeSafe i (toRuby v) >>= \r -> case r of
                                                   Right r' -> return r'
                                                   Left rr -> error (show rr)
        nxt <- safeMethodCall i "TestClass" "testfunc" [rub]
        case nxt of
            Right x -> do
                out <- makeSafe i (fromRuby x) >>= \r -> case r of
                                                             Right r' -> return r'
                                                             Left rr -> error (show rr)
                when (out /= Just v) (print out)
                return (Just v == out)
            Left rr -> print rr >> return False
    assert ex

main :: IO ()
main = do
    i <- startRubyInterpreter
    putStrLn "loading"
    loadFile i "./test/test.rb" >>= \o -> case o of
                                            Right () -> return ()
                                            Left rr -> error (show rr)
    quickCheckWith (stdArgs { maxSuccess = 1000 } ) (roundTrip i)
    closeRubyInterpreter i
