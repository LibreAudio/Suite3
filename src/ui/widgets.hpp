// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "reference/image.hpp"
#include "base/interface.hpp"
#include "reference/button-group.hpp"
#include "widgets/base.hpp"
#include "widgets/root.hpp"
#include "widgets-todo/button.hpp"
#include "widgets-todo/meter.hpp"
#include "widgets-todo/stage.hpp"
#include "widgets-todo/top-bar-name.hpp"

#include "las-resources.h"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

using LibreAudioTopBarLogoWidget = LibreAudioImageWidget<IMAGES_LA_PNG_DATA, IMAGES_LA_PNG_LEN>;
using LibreAudioButtonGroupWidget = LibreAudioReferenceButtonGroupWidget<LibreAudioReference::Widgets::ButtonGroup>;

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBarUndoRedoGroupWidget : public LibreAudioButtonGroupWidget
{
    std::shared_ptr<LibreAudioButtonWidget> fUndo = addButton<LibreAudioImageButtonWidget<LibreAudioButtonWidget::kCornerLeft, IMAGES_UNDO_PNG_DATA, IMAGES_UNDO_PNG_LEN>>(kWidgetUndo);
    std::shared_ptr<LibreAudioButtonWidget> fRedo = addButton<LibreAudioImageButtonWidget<LibreAudioButtonWidget::kCornerRight, IMAGES_REDO_PNG_DATA, IMAGES_REDO_PNG_LEN>>(kWidgetRedo);

public:
    explicit LibreAudioTopBarUndoRedoGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioButtonGroupWidget(parent)
    {
        done();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBarSnapshotsGroupWidget : public LibreAudioButtonGroupWidget
{
    static constexpr const char kTextA[] = "A";
    static constexpr const char kTextB[] = "B";
    static constexpr const char kTextC[] = "C";
    static constexpr const char kTextD[] = "D";
    std::shared_ptr<LibreAudioButtonWidget> fCopy = addButton<LibreAudioDualImageButtonWidget<
        LibreAudioButtonWidget::kCornerLeft, IMAGES_X_PNG_DATA, IMAGES_X_PNG_LEN, IMAGES_COPY_PNG_DATA, IMAGES_COPY_PNG_LEN>>(kWidgetSnapshotCopy);
    std::shared_ptr<LibreAudioButtonWidget> fA = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerNone, kTextA>>(kWidgetSnapshotSlotA);
    std::shared_ptr<LibreAudioButtonWidget> fB = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerNone, kTextB>>(kWidgetSnapshotSlotB);
    std::shared_ptr<LibreAudioButtonWidget> fC = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerNone, kTextC>>(kWidgetSnapshotSlotC);
    std::shared_ptr<LibreAudioButtonWidget> fD = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerRight, kTextD>>(kWidgetSnapshotSlotD);

public:
    explicit LibreAudioTopBarSnapshotsGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioButtonGroupWidget(parent)
    {
        fA->setWidth(fCopy->getWidth());
        fB->setWidth(fCopy->getWidth());
        fC->setWidth(fCopy->getWidth());
        fD->setWidth(fCopy->getWidth());
        done();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBarEasyExpertGroupWidget : public LibreAudioButtonGroupWidget
{
    static constexpr const char kTextEasy[] = "Easy";
    static constexpr const char kTextExpert[] = "Expert";
    std::shared_ptr<LibreAudioButtonWidget> fEasy = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerLeft, kTextEasy>>(kWidgetEasy);
    std::shared_ptr<LibreAudioButtonWidget> fExpert = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerRight, kTextExpert>>(kWidgetExpert);

public:
    explicit LibreAudioTopBarEasyExpertGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioButtonGroupWidget(parent)
    {
        done();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBarMenuPowerGroupWidget : public LibreAudioButtonGroupWidget
{
    std::shared_ptr<LibreAudioButtonWidget> fMenu = addButton<LibreAudioImageButtonWidget<LibreAudioButtonWidget::kCornerLeft, IMAGES_MENU_PNG_DATA, IMAGES_MENU_PNG_LEN>>(kWidgetMenu);
    std::shared_ptr<LibreAudioButtonWidget> fPower = addButton<LibreAudioBypassButtonWidget<LibreAudioButtonWidget::kCornerRight>>(kWidgetPower);

public:
    explicit LibreAudioTopBarMenuPowerGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioButtonGroupWidget(parent)
    {
        done();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBar : public LibreAudioReferenceContainerWidget<LibreAudioReference::TopBar>
{
    std::unique_ptr<LibreAudioTopBarLogoWidget> fLogo = addWidget<LibreAudioTopBarLogoWidget>();
    std::unique_ptr<LibreAudioTopBarNameWidget> fPluginName = addWidget<LibreAudioTopBarNameWidget>();
    std::unique_ptr<LibreAudioWidget> fSpacer = addSpacer();
    std::unique_ptr<LibreAudioButtonGroupWidget> fUndoRedoGroup = addWidget<LibreAudioTopBarUndoRedoGroupWidget>();
    std::unique_ptr<LibreAudioButtonGroupWidget> fSnapshotsGroup = addWidget<LibreAudioTopBarSnapshotsGroupWidget>();
    std::unique_ptr<LibreAudioButtonGroupWidget> fEasyExpertGroup = addWidget<LibreAudioTopBarEasyExpertGroupWidget>();
    std::unique_ptr<LibreAudioButtonGroupWidget> fMenuPowerGroup = addWidget<LibreAudioTopBarMenuPowerGroupWidget>();

public:
    LibreAudioTopBar(LibreAudioTopLevelWidget* const parent)
        : LibreAudioReferenceContainerWidget(parent)
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioMainArea : public LibreAudioReferenceContainerWidget<LibreAudioReference::MainArea>
{
    std::unique_ptr<LibreAudioWidget> fMetersIn = addWidget<LibreAudioMeterWidget<Input>>();
    std::unique_ptr<LibreAudioStageWidget> fStage = addWidget<LibreAudioStageWidget, Expanding>();
    std::unique_ptr<LibreAudioWidget> fMetersOut = addWidget<LibreAudioMeterWidget<Output>>();

public:
    LibreAudioMainArea(LibreAudioTopLevelWidget* const parent)
        : LibreAudioReferenceContainerWidget(parent)
    {
    }

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

END_NAMESPACE_DISTRHO
