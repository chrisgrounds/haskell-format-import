{-# LANGUAGE OverloadedStrings #-}

module HaskellFormatImport.Plugin ( haskellFormatImport ) where

import Basement.IntegralConv (intToInt64)
import Data.Char
import Data.List
import Data.List.Split
import Data.Maybe            (maybe, fromMaybe)
import Neovim
import Neovim.API.String
import Text.Regex

-- | Qualification in this context means that one of the imports is a qualified import
-- It is a property that applies to the whole buffer, however.
data Qualification = Present | NotPresent

newtype MaxLineLength = MaxLineLength Int

newtype LineNumber = LineNumber Int

instance Enum LineNumber where
  toEnum                  = LineNumber
  fromEnum (LineNumber a) = fromEnum a

moduleNameRegex :: Regex
moduleNameRegex = mkRegex "^import\\s[qualified]*\\s*([[:alpha:][:punct:]]+)"

importRegex :: Regex
importRegex = mkRegex "^import\\s"

qualifiedPadLength :: Int
qualifiedPadLength = 10

haskellFormatImport :: CommandArguments -> Neovim env ()
haskellFormatImport (CommandArguments _ range _ _) = do
  let (startOfRange, endOfRange) = fromMaybe (0,0) range
  buff     <- vim_get_current_buffer
  allLines <- nvim_buf_get_lines buff (intToInt64 startOfRange) (intToInt64 endOfRange) False

  let allImportLines       = sortImports . filter isImportStatement . zip [LineNumber 1..LineNumber endOfRange] $ allLines
      anyImportIsQualified = getQualification allImportLines
      maxLineLength        = MaxLineLength $ foldr max 0 $ fmap (\(_,s) -> length s) allImportLines
      longestModuleName    = getLongestModuleName allImportLines

  mapM_ (formatImportLine buff anyImportIsQualified maxLineLength longestModuleName) allImportLines >> return ()

emptyQualified :: String
emptyQualified = take qualifiedPadLength $ repeat ' '

getLongestModuleName :: [(LineNumber, String)] -> Int
getLongestModuleName xs 
  = maximum $ fmap (fromMaybe 0 . getLengthOfModuleName . snd) xs

formatImportLine :: Buffer -> Qualification -> MaxLineLength -> Int -> (LineNumber, String) -> Neovim env ()
formatImportLine buff qualifiedImports (MaxLineLength longestImport) longestModuleName (LineNumber lineNo, lineContent) 
  = buffer_set_line buff (intToInt64 lineNo) $ padContent lineContent qualifiedImports longestImport longestModuleName

getQualification :: [(LineNumber, String)] -> Qualification
getQualification xs = go $ filter isQualified xs
  where
    go [] = NotPresent
    go _  = Present

padContent :: String -> Qualification -> Int -> Int -> String
padContent content NotPresent longestImport longestModuleName = padAs longestModuleName content
padContent content Present longestImport longestModuleName =
  if "qualified" `isInfixOf` content || ("import" ++ emptyQualified) `isInfixOf` content
     then padAs longestModuleName content
     else padAs longestModuleName $ concat $ ("import" ++ emptyQualified) : splitOn "import" content

getLengthOfModuleName :: String -> Maybe Int
getLengthOfModuleName s = do
    let match = matchRegex moduleNameRegex s
    case match of
      Just m  -> return $ length .concat $ m
      Nothing -> error $ s ++ " does not match the import regex!"
                           ++ " Please raise an issue on the github page"
                           ++ " quoting what statement it failed on"

padAs :: Int -> String -> String
padAs n s =
    let lenModName = fromMaybe 0 $ getLengthOfModuleName s
        padDiff    = n - lenModName 
     in mconcat . intersperse (take padDiff (repeat ' ') ++ " as ") $ splitOn " as " s

sortImports :: [(LineNumber, String)] -> [(LineNumber, String)]
sortImports xs = zip (fmap fst xs) $ sortBy (\a b -> compare (toLower <$> ignoreQualified a) (toLower <$> ignoreQualified b)) (fmap snd xs)
  where
    ignoreQualified = concat . splitOn "qualified"

isImportStatement :: (LineNumber, String) -> Bool
isImportStatement (_, s) = maybe False (const True) $ matchRegex importRegex s  

isQualified :: (LineNumber, String) -> Bool
isQualified (_, s) = isInfixOf "qualified " s

