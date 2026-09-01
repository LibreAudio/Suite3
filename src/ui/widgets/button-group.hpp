// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"
#include "../reference.hpp"
#include "../reference/button-group.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class ButtonGroupWidget : public ReferenceButtonGroupWidget<Reference::Widgets::ButtonGroup>
{
    using BaseWidget = ReferenceButtonGroupWidget<Reference::Widgets::ButtonGroup>;

public:
    explicit ButtonGroupWidget(Widget* const parent)
        : BaseWidget(parent)
    {
    }

    template<class B, typename = std::enable_if_t<std::is_base_of_v<ButtonBaseWidget, B>>>
    std::shared_ptr<ButtonBaseWidget> addButton(const WidgetIds id)
    {
        return BaseWidget::addButton<B>(id, WidgetIds2Str(id));
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */

