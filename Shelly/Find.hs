{-# LANGUAGE OverloadedStrings #-}
-- | File finding utiliites for Shelly
-- The basic 'find' takes a dir and gives back a list of files.
-- If you don't just want a list, use the folding variants like 'findFold'.
-- If you want to avoid traversing certain directories, use the directory filtering variants like 'findDirFilter'
module Shelly.Find
 (
   find, findWhen, findFold, findDirFilter, findDirFilterWhen, findFoldDirFilter
 ) where

import Prelude hiding (FilePath)
import Shelly.Base
import Control.Monad (foldM)
import Data.Monoid (mappend)
import System.PosixCompat.Files( getSymbolicLinkStatus, isSymbolicLink )
import Filesystem (isDirectory)

-- | List directory recursively (like the POSIX utility "find").
-- listing is relative if the path given is relative.
-- If you want to filter out some results or fold over them you can do that with the returned files.
-- A more efficient approach is to use one of the other find functions.
find :: FilePath -> Sh [FilePath]
find = findFold (\paths fp -> return $ paths ++ [fp]) []

-- | 'find' that filters the found files as it finds.
-- Files must satisfy the given filter to be returned in the result.
findWhen :: (FilePath -> Sh Bool) -> FilePath -> Sh [FilePath]
findWhen = findDirFilterWhen (const $ return True)

-- | Fold an arbitrary folding function over files froma a 'find'.
-- Like 'findWhen' but use a more general fold rather than a filter.
findFold :: (a -> FilePath -> Sh a) -> a -> FilePath -> Sh a
findFold folder startValue = findFoldDirFilter folder startValue (const $ return True)

-- | 'find' that filters out directories as it finds
-- Filtering out directories can make a find much more efficient by avoiding entire trees of files.
findDirFilter :: (FilePath -> Sh Bool) -> FilePath -> Sh [FilePath]
findDirFilter filt = findDirFilterWhen filt (const $ return True)

-- | similar 'findWhen', but also filter out directories
-- Alternatively, similar to 'findDirFilter', but also filter out files
-- Filtering out directories makes the find much more efficient
findDirFilterWhen :: (FilePath -> Sh Bool) -- ^ directory filter
                  -> (FilePath -> Sh Bool) -- ^ file filter
                  -> FilePath -- ^ directory
                  -> Sh [FilePath]
findDirFilterWhen dirFilt fileFilter = findFoldDirFilter filterIt [] dirFilt
  where
    filterIt paths fp = do
      yes <- fileFilter fp
      return $ if yes then paths ++ [fp] else paths

-- | like 'findDirFilterWhen' but use a folding function rather than a filter
-- The most general finder: you likely want a more specific one
findFoldDirFilter :: (a -> FilePath -> Sh a) -> a -> (FilePath -> Sh Bool) -> FilePath -> Sh a
findFoldDirFilter folder startValue dirFilter dir = do
  absDir <- absPath dir
  trace ("find " `mappend` toTextIgnore absDir)
  filt <- dirFilter absDir
  if filt
    -- use possible relative path, not absolute so that listing will remain relative
    then ls dir >>= foldM traverse startValue
    else return startValue
  where
    traverse acc x = do
      -- optimization: don't use Shelly API since our path is already good
      isDir <- liftIO $ isDirectory x
      sym   <- liftIO $ fmap isSymbolicLink $ getSymbolicLinkStatus (unpack x)
      if isDir && not sym
        then findFold folder acc x
        else folder acc x