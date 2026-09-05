// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "lab/image.hpp"
#include "lab/interface.hpp"
#include "widgets/base.hpp"
#include "widgets/button-group.hpp"
#include "widgets/meter.hpp"
#include "widgets/plugin-name.hpp"
#include "widgets/root.hpp"
#include "widgets-todo/button.hpp"
#include "widgets-todo/stage.hpp"

#include "las-resources.h"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

using TopBarLogoWidget = LabImageWidget<IMAGES_LA_PNG_DATA, IMAGES_LA_PNG_LEN>;

// --------------------------------------------------------------------------------------------------------------------

class TopBarUndoRedoGroupWidget : public ButtonGroupWidget
{
    std::shared_ptr<ButtonBaseWidget> fUndo = addButton<ImageButtonWidget<kCornerLeft, IMAGES_UNDO_PNG_DATA, IMAGES_UNDO_PNG_LEN>>(kWidgetUndo);
    std::shared_ptr<ButtonBaseWidget> fRedo = addButton<ImageButtonWidget<kCornerRight, IMAGES_REDO_PNG_DATA, IMAGES_REDO_PNG_LEN>>(kWidgetRedo);

public:
    explicit TopBarUndoRedoGroupWidget(LabWidget* const parent)
        : ButtonGroupWidget(parent)
    {
        done();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class TopBarSnapshotsGroupWidget : public ButtonGroupWidget
{
    static constexpr const char kTextA[] = "A";
    static constexpr const char kTextB[] = "B";
    static constexpr const char kTextC[] = "C";
    static constexpr const char kTextD[] = "D";
    std::shared_ptr<ButtonBaseWidget> fCopy = addButton<DualImageButtonWidget<
        kCornerLeft, IMAGES_X_PNG_DATA, IMAGES_X_PNG_LEN, IMAGES_COPY_PNG_DATA, IMAGES_COPY_PNG_LEN>>(kWidgetSnapshotCopy);
    std::shared_ptr<ButtonBaseWidget> fA = addButton<StaticTextButtonWidget<kCornerNone, kTextA>>(kWidgetSnapshotSlotA);
    std::shared_ptr<ButtonBaseWidget> fB = addButton<StaticTextButtonWidget<kCornerNone, kTextB>>(kWidgetSnapshotSlotB);
    std::shared_ptr<ButtonBaseWidget> fC = addButton<StaticTextButtonWidget<kCornerNone, kTextC>>(kWidgetSnapshotSlotC);
    std::shared_ptr<ButtonBaseWidget> fD = addButton<StaticTextButtonWidget<kCornerRight, kTextD>>(kWidgetSnapshotSlotD);

public:
    explicit TopBarSnapshotsGroupWidget(LabWidget* const parent)
        : ButtonGroupWidget(parent)
    {
        fA->setWidth(fCopy->getWidth());
        fB->setWidth(fCopy->getWidth());
        fC->setWidth(fCopy->getWidth());
        fD->setWidth(fCopy->getWidth());
        done();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class TopBarEasyExpertGroupWidget : public ButtonGroupWidget
{
    static constexpr const char kTextEasy[] = "Easy";
    static constexpr const char kTextExpert[] = "Expert";
    std::shared_ptr<LabWidget> fEasy = addButton<StaticTextButtonWidget<kCornerLeft, kTextEasy>>(kWidgetEasy);
    std::shared_ptr<LabWidget> fExpert = addButton<StaticTextButtonWidget<kCornerRight, kTextExpert>>(kWidgetExpert);

public:
    explicit TopBarEasyExpertGroupWidget(LabWidget* const parent)
        : ButtonGroupWidget(parent)
    {
        done();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class TopBarMenuPowerGroupWidget : public ButtonGroupWidget
{
    std::shared_ptr<LabWidget> fMenu = addButton<ImageButtonWidget<kCornerLeft, IMAGES_MENU_PNG_DATA, IMAGES_MENU_PNG_LEN>>(kWidgetMenu);
    std::shared_ptr<LabWidget> fPower = addButton<BypassButtonWidget<kCornerRight>>(kWidgetPower);

public:
    explicit TopBarMenuPowerGroupWidget(LabWidget* const parent)
        : ButtonGroupWidget(parent)
    {
        done();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class TopBar : public ReferenceContainerWidget<Reference::TopBar>
{
    using BaseWidget = ReferenceContainerWidget<Reference::TopBar>;

    std::shared_ptr<LabWidget> fLogo = addWidget<TopBarLogoWidget>();
    std::shared_ptr<LabWidget> fPluginName = addWidget<PluginNameWidget>();
    std::shared_ptr<LabWidget> fSpacer = addSpacer();
    std::shared_ptr<LabWidget> fUndoRedoGroup = addWidget<TopBarUndoRedoGroupWidget>();
    std::shared_ptr<LabWidget> fSnapshotsGroup = addWidget<TopBarSnapshotsGroupWidget>();
    std::shared_ptr<LabWidget> fEasyExpertGroup = addWidget<TopBarEasyExpertGroupWidget>();
    std::shared_ptr<LabWidget> fMenuPowerGroup = addWidget<TopBarMenuPowerGroupWidget>();

public:
    TopBar(LabTopLevelWidget* const parent)
        : BaseWidget(parent)
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------

class MainArea : public ReferenceContainerWidget<Reference::MainArea>
{
    using BaseWidget = ReferenceContainerWidget<Reference::MainArea>;

    std::shared_ptr<LabWidget> fMetersIn = addWidget<MeterWidget<Input>>();
    std::shared_ptr<StageWidget> fStage = addWidget<StageWidget, Expanding>();
    std::shared_ptr<LabWidget> fMetersOut = addWidget<MeterWidget<Output>>();

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
