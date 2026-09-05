// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "container.hpp"

START_NAMESPACE_DGL

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
    RootReferenceTopLevelWidget(Window& window, LabUIWidgetInterface* const iface)
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

END_NAMESPACE_DGL
