{-# LANGUAGE OverloadedStrings #-}

module Compounds (loadCompounds) where

import qualified Data.Text.IO as TIO
import qualified Data.Text as T
import Data.Text (Text, pack, append)
import GHC.IO.Handle.FD (stderr)
import qualified Data.ByteString.Lazy as L
import Text.XML.Expat.Tree
import qualified Data.Map.Lazy as M
import Data.Maybe (catMaybes, Maybe(Just))

import Types
import XmlHelper

loadCompounds :: Bool -> Text -> FilePath -> FilePath -> IO (Kanji -> Kanji)
loadCompounds noDictFilling lang freqListPath jmdicPath = do
  jmdicRaw <- L.readFile jmdicPath
  let (jmdic, mErr) = parse defaultParseOptions jmdicRaw :: (NodeG [] Text Text, Maybe XMLParseError)

  freqList <- fmap T.lines $ TIO.readFile freqListPath
  let cmap = compoundsMap lang jmdic

  let wordList = if noDictFilling then freqList else (freqList ++ M.keys cmap)

  let compounds kanji = take 6 $ catMaybes $ fmap (\w -> M.lookup w cmap) $ filter (T.any (== char kanji)) $ wordList
  let kanjiWithCompounds = \k -> k { compounds = compounds k }

  case mErr of
    Nothing -> return kanjiWithCompounds
    Just err -> do
      TIO.hPutStrLn stderr $ "XML parse failed: " `append` (pack $ show err)
      return id

compoundsMap :: Text -> NodeG [] Text Text -> M.Map Text Compound
compoundsMap lang jmdic = M.fromListWith selectFirst $ concatMap (toCompounds lang) $ filterDeepNodes ["entry"] jmdic

selectFirst c0@(Compound uid0 _ _ _) c1@(Compound uid1 _ _ _)
  | uid0 < uid1 = c0
  | otherwise = c1

toCompounds :: Text -> NodeG [] Text Text -> [(Text, Compound)]
toCompounds lang node = catMaybes $ fmap (\k -> toCompound lang k node) kebs
  where
    kebs = fmap unsafeText $ filterDeepNodes ["k_ele", "keb"] node

toCompound :: Text -> Text -> NodeG [] Text Text -> Maybe (Text, Compound)
toCompound lang keb node
  | translations == [] = Nothing
  | otherwise = Just $ (keb, Compound uid keb reading $ head translations)
  where
    uid = read $ T.unpack $ unsafeText $ head $ filterDeepNodes ["ent_seq"] node
    reading = unsafeText $ head $ filterDeepNodes ["r_ele", "reb"] node
    translations = catMaybes $ fmap (toSense lang) $ filterDeepNodes ["sense"] node

langFilter "fr" = attrFilter "xml:lang" "fre"
langFilter _ = attrFilter "xml:lang" "eng"

toSense :: Text -> NodeG [] Text Text -> Maybe [Text]
toSense lang node
  | glosss == [] = Nothing
  | otherwise = Just $ fmap unsafeText glosss
  where
    glosss = filter (langFilter lang) $ filterDeepNodes ["gloss"] node
