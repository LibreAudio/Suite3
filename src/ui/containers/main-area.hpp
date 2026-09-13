// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// #include "base.hpp"
#include "../containers/root.hpp"
#include "../containers/stage.hpp"
#if LIBREAUDIO_WANT_COMMON_IO
#include "../widgets/gain-meter.hpp"
#endif

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

template<class StageWidget = StageWidget<>>
class MainArea : public ReferenceContainerWidget<Reference::MainArea>
{
    using BaseWidget = ReferenceContainerWidget<Reference::MainArea>;

   #if LIBREAUDIO_WANT_COMMON_IO
    std::shared_ptr<LabWidget> fMetersIn = addWidget<GainMeterWidget<Input>>();
   #endif
    std::shared_ptr<StageWidget> fStage = addWidget<StageWidget, Expanding>();
   #if LIBREAUDIO_WANT_COMMON_IO
    std::shared_ptr<LabWidget> fMetersOut = addWidget<GainMeterWidget<Output>>();
   #endif

public:
    MainArea(LabTopLevelWidget* const parent)
        : BaseWidget(parent) {}

    [[nodiscard]] Point<int> getMainAreaAbsolutePos() const noexcept
    {
        return fStage->getAbsolutePos();
    }

    [[nodiscard]] Size<uint> getMainAreaSize() const noexcept
    {
        return fStage->getSize();
    }

    [[nodiscard]] float getMainAreaBorderRadius() const noexcept
    {
        return fStage->getBorderRadius();
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
