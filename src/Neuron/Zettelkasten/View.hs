{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE NoImplicitPrelude #-}

-- | HTML & CSS
module Neuron.Zettelkasten.View where

import Clay hiding (reverse, s)
import qualified Clay as C
import Data.Foldable (maximum)
import qualified Data.Set as Set
import Data.Tree (Tree (..))
import Lucid
import Neuron.Zettelkasten.Graph
import Neuron.Zettelkasten.ID
import Neuron.Zettelkasten.Link (LinkTheme (..), renderZettelLink, zettelLinkExt)
import Neuron.Zettelkasten.Route
import Neuron.Zettelkasten.Store
import Neuron.Zettelkasten.Type
import Relude
import qualified Text.MMark as MMark

renderRoute :: Route store graph a -> (store, graph) -> Html ()
renderRoute r val = do
  case r of
    Route_Index ->
      renderIndex val
    Route_Zettel zid ->
      renderZettel val zid

renderIndex :: (ZettelStore, ZettelGraph) -> Html ()
renderIndex (store, graph) = do
  h1_ [class_ "header"] $ "Zettel Index"
  div_ [class_ "zettels"] $ do
    -- cluster
    forM_ (reverse $ clusters graph) $ \zettels -> do
      when (length zettels > 1) $ do
        h2_ "Cluster"
        hr_ mempty
        forM_ zettels $ \zid ->
          li_ $ do
            renderZettelLink LinkTheme_Default store zid
    let forest = dfsForest indexZettelID graph
        categorizedZids = Set.fromList $ concatMap toList forest
    -- cycles and dangling checks
    case topSort graph of
      Left (toList -> cyc) -> div_ [class_ "ui piled segment"] $ do
        h2_ "Cycle detected"
        forM_ cyc $ \zid ->
          li_ $ renderZettelLink LinkTheme_Default store zid
        hr_ mempty
      Right (Set.fromList -> allZids) -> do
        let danglingZids = allZids `Set.difference` categorizedZids
        unless (null danglingZids) $ do
          h2_ "Dangling zettels"
          ul_
            $ forM_ danglingZids
            $ \zid ->
              li_ $ renderZettelLink LinkTheme_Default store zid
    -- tree
    h2_ "Tree"
    ul_ $ renderForest LinkTheme_Default store graph forest

renderZettel :: (ZettelStore, ZettelGraph) -> ZettelID -> Html ()
renderZettel (store, graph) zid = do
  let Zettel {..} = lookupStore zid store
  div_ [class_ "zettel-view"] $ do
    div_ [class_ "ui raised segment"] $ do
      h1_ [class_ "header"] $ toHtml zettelTitle
      MMark.render $ MMark.useExtension (zettelLinkExt store) zettelContent
    div_ [class_ "ui inverted teal stacked segment connections"] $ do
      div_ $ b_ "Connections"
      div_ [class_ "ui two column grid"] $ do
        div_ [class_ "column"] $ do
          let forest = dfsForest zid graph
          ul_ $ renderForest (LinkTheme_Menu zid) store graph forest
        div_ [class_ "column"] $ do
          let forestB = dfsForestBackwards zid graph
          ul_ $ renderForest (LinkTheme_Menu zid) store graph forestB

renderForest :: LinkTheme -> ZettelStore -> ZettelGraph -> [Tree ZettelID] -> Html ()
renderForest ltheme s g trees =
  forM_ (sortForest trees) $ \(Node zid subtrees) ->
    li_ $ do
      renderZettelLink ltheme s zid
      when (ltheme == LinkTheme_Default) $ do
        " "
        case backlinks zid g of
          [] -> unless (zid == indexZettelID) $ div_ [class_ "ui red label"] "DANGLING"
          [_] -> mempty
          conns ->
            forM_ conns $ \zid2 -> do
              let z2 = lookupStore zid2 s
              i_ [class_ "fas fa-link", title_ $ unZettelID zid2 <> " " <> zettelTitle z2] mempty
      when (length subtrees > 0) $ do
        ul_ $ renderForest ltheme s g subtrees
  where
    -- Sort trees so that trees containing the most recent zettel (by ID) come first.
    sortForest = reverse . sortOn maximum

style :: Css
style = do
  let linkColor = C.mediumaquamarine
      linkTitleColor = C.auto
  "span.zettel-link span.zettel-link-idlink a" ? do
    C.fontFamily [] [C.monospace]
    C.fontWeight C.bold
    C.color linkColor
    C.textDecoration C.none
  "span.zettel-link span.zettel-link-idlink a:hover" ? do
    C.backgroundColor linkColor
    C.color C.white
  ".zettel-link .zettel-link-title" ? do
    C.paddingLeft $ em 0.3
    C.fontWeight C.bold
    C.color linkTitleColor
  "div.zettel-view" ? do
    C.ul ? do
      C.paddingLeft $ em 1.5
      C.listStyleType C.square
      C.li ? do
        mempty -- C.paddingBottom $ em 1
    C.h1 ? do
      C.paddingTop $ em 0.2
      C.paddingBottom $ em 0.2
      C.textAlign C.center
      C.color C.midnightblue
      C.fontWeight C.bold
      C.backgroundColor C.whitesmoke
    C.h2 ? do
      C.fontColor C.darkslategray
      C.fontWeight C.bold
      C.borderBottom C.solid (px 1) C.steelblue
      C.marginBottom $ em 0.5
    C.h3 ? do
      C.fontColor C.slategray
      C.fontWeight C.bold
      C.margin (px 0) (px 0) (em 0.4) (px 0)
    codeStyle
    blockquoteStyle
  "div.connections" ? do
    mempty
  where
    codeStyle = do
      C.code ? do
        sym margin auto
        fontSize $ pct 90
      "code, pre, tt" ? do
        fontFamily ["SFMono-Regular", "Menlo", "Monaco", "Consolas", "Liberation Mono", "Courier New"] [monospace]
      pre ? do
        sym padding $ em 0.5
      "div.source-code" ? do
        marginLeft auto
        marginRight auto
        maxWidth $ pct 80
        pre ? do
          backgroundColor "#f8f8f8"
    -- https://css-tricks.com/snippets/css/simple-and-nice-blockquote-styling/
    blockquoteStyle = do
      C.blockquote ? do
        -- TODO: quotes in clay?
        C.backgroundColor "#f9f9f9"
        C.borderLeft C.solid (px 10) "#ccc"
        sym2 C.margin (em 1.5) (px 10)
        sym2 C.padding (em 0.5) (px 10)
        C.p ? do
          C.display C.inline
      "blockquote:before" ? do
        C.color "#ccc"
        C.content C.openQuote
        C.fontSize $ em 4
        C.lineHeight $ em 0.1
        C.marginRight $ em 0.25
        C.verticalAlign $ em $ -0.4
