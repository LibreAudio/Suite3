// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "container.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class RootWidgetInterface
{
public:
    virtual ~RootWidgetInterface() = default;
    virtual void updateScaleFactorAndSize() = 0;
};

// --------------------------------------------------------------------------------------------------------------------

template<class R, Orientation orientation>
class RootReferenceTopLevelWidget : public ReferenceContainerTopLevelWidget<R, orientation>,
                                    public RootWidgetInterface
{
    using BaseWidget = ReferenceContainerTopLevelWidget<R, orientation>;
    using ResizeEvent = typename BaseWidget::ResizeEvent;

public:
    RootReferenceTopLevelWidget(Window& window, UIWidgetInterface* const iface)
        : BaseWidget(window, iface) {}

    void updateScaleFactorAndSize() final
    {
        BaseWidget::updateScaleFactor(this->fInterface->getScaleFactor());
        this->updateSize(true);
    }

private:
    void onResize(const ResizeEvent& ev) final
    {
        BaseWidget::onResize(ev);
        updateScaleFactorAndSize();
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
