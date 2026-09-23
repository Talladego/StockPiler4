----------------------------------------------------------------
-- StockPiler4 BrewChrome -- footer / row brew paint requests
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.BrewChrome = StockPiler4.BrewChrome or {}
local BrewChrome = StockPiler4.BrewChrome

function BrewChrome.RefreshBrewUi()
    local Brew = StockPiler4.Brew
    if Brew and Brew._suppressBrewUi == true then
        return
    end
    if Brew and Brew.InvalidateCanBrewCache then
        Brew.InvalidateCanBrewCache()
    end
    if StockPiler4.Perf and StockPiler4.Perf.Begin then
        StockPiler4.Perf.Begin("BrewUi")
    end
    if StockPiler4Window and StockPiler4Window.RequestFooterRefresh then
        StockPiler4Window.RequestFooterRefresh()
    elseif StockPiler4Window and StockPiler4Window.RefreshFooterButtons then
        StockPiler4Window.RefreshFooterButtons()
    end
    if StockPiler4TabWatch and StockPiler4TabWatch.InvalidateBrewChrome then
        StockPiler4TabWatch.InvalidateBrewChrome()
    end
    if StockPiler4.Ui and StockPiler4.Ui.MarkWatchUiDirty then
        StockPiler4.Ui.MarkWatchUiDirty()
    end
    if StockPiler4Window and StockPiler4Window.RequestListRepopulate then
        StockPiler4Window.RequestListRepopulate()
    end
    if Brew and Brew.MaybeNotifyBrewReady then
        Brew.MaybeNotifyBrewReady()
    end
    if StockPiler4.Perf and StockPiler4.Perf.End then
        StockPiler4.Perf.End("BrewUi")
    end
end
