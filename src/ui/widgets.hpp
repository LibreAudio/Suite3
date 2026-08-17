// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base/image.hpp"
#include "base/interface.hpp"
#include "base/button-group.hpp"
#include "widgets-todo/button.hpp"
// #include "widgets/knob.hpp"
// #include "widgets/knob-group.hpp"
// #include "widgets/line.hpp"
// #include "widgets/meter.hpp"
// #include "widgets/pill-toggle.hpp"
// #include "widgets/shader.hpp"
// #include "widgets/stage.hpp"
// #include "widgets/top-bar-name.hpp"

#include "LibreAudioParameters.hpp"

#include "las-resources.h"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

enum WidgetIds {
    kWidgetIdStart = 1000,
    kWidgetUndo,
    kWidgetRedo,
    kWidgetSnapshotCopy,
    kWidgetSnapshotA,
    kWidgetSnapshotB,
    kWidgetSnapshotC,
    kWidgetSnapshotD,
    kWidgetEasy,
    kWidgetExpert,
    kWidgetMenu,
    kWidgetPower,
};

// --------------------------------------------------------------------------------------------------------------------

using LibreAudioTopBarLogoWidget = LibreAudioImageWidget<IMAGES_LA_PNG_DATA, IMAGES_LA_PNG_LEN>;
using LibreAudioButtonGroupWidget = LibreAudioReferenceButtonGroupWidget<LibreAudioReference::Widgets::ButtonGroup>;

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBarUndoRedoGroupWidget : public LibreAudioButtonGroupWidget,
                                            private ButtonEventHandler::Callback,
                                            private IdleCallback
{
    std::unique_ptr<LibreAudioButtonWidget> fUndo = addButton<LibreAudioImageButtonWidget<LibreAudioButtonWidget::kCornerLeft, IMAGES_UNDO_PNG_DATA, IMAGES_UNDO_PNG_LEN>>(kWidgetUndo);
    std::unique_ptr<LibreAudioButtonWidget> fRedo = addButton<LibreAudioImageButtonWidget<LibreAudioButtonWidget::kCornerRight, IMAGES_REDO_PNG_DATA, IMAGES_REDO_PNG_LEN>>(kWidgetRedo);

public:
    explicit LibreAudioTopBarUndoRedoGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioButtonGroupWidget(parent)
    {
        done(this);

        update();
        addIdleCallback(this);
    }

private:
    void buttonClicked(SubWidget* const widget, int) final
    {
        switch (widget->getId())
        {
        case kWidgetUndo:
            fInterface->undo();
            break;
        case kWidgetRedo:
            fInterface->redo();
            break;
        }

        update();
    }

    void idleCallback() final
    {
        update();
    }

    void update()
    {
        fUndo->setEnabled(fInterface->canUndo());
        fRedo->setEnabled(fInterface->canRedo());
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBarSnapshotsGroupWidget : public LibreAudioButtonGroupWidget,
                                             private ButtonEventHandler::Callback,
                                             private IdleCallback
{
    static constexpr const char kTextA[] = "A";
    static constexpr const char kTextB[] = "B";
    static constexpr const char kTextC[] = "C";
    static constexpr const char kTextD[] = "D";
    std::unique_ptr<LibreAudioButtonWidget> fCopy = addButton<LibreAudioDualImageButtonWidget<
        LibreAudioButtonWidget::kCornerLeft, IMAGES_X_PNG_DATA, IMAGES_X_PNG_LEN, IMAGES_COPY_PNG_DATA, IMAGES_COPY_PNG_LEN>>(kWidgetSnapshotCopy);
    std::unique_ptr<LibreAudioButtonWidget> fA = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerNone, kTextA>>(kWidgetSnapshotA);
    std::unique_ptr<LibreAudioButtonWidget> fB = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerNone, kTextB>>(kWidgetSnapshotB);
    std::unique_ptr<LibreAudioButtonWidget> fC = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerNone, kTextC>>(kWidgetSnapshotC);
    std::unique_ptr<LibreAudioButtonWidget> fD = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerRight, kTextD>>(kWidgetSnapshotD);

public:
    explicit LibreAudioTopBarSnapshotsGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioButtonGroupWidget(parent)
    {
        fA->setWidth(fCopy->getWidth());
        fB->setWidth(fCopy->getWidth());
        fC->setWidth(fCopy->getWidth());
        fD->setWidth(fCopy->getWidth());
        done(this);

        fCopy->setCheckable(true);
        fA->setCheckable(true);
        fB->setCheckable(true);
        fC->setCheckable(true);
        fD->setCheckable(true);

        update();
        addIdleCallback(this);
    }

private:
    void buttonClicked(SubWidget* const widget, int) final
    {
        switch (widget->getId())
        {
        case kWidgetSnapshotCopy:
            fInterface->snapshotButtonClicked(LibreAudioUIWidgetInterface::kSnapshotButtonCopy);
            break;
        case kWidgetSnapshotA:
            fInterface->snapshotButtonClicked(LibreAudioUIWidgetInterface::kSnapshotButtonA);
            break;
        case kWidgetSnapshotB:
            fInterface->snapshotButtonClicked(LibreAudioUIWidgetInterface::kSnapshotButtonB);
            break;
        case kWidgetSnapshotC:
            fInterface->snapshotButtonClicked(LibreAudioUIWidgetInterface::kSnapshotButtonC);
            break;
        case kWidgetSnapshotD:
            fInterface->snapshotButtonClicked(LibreAudioUIWidgetInterface::kSnapshotButtonD);
            break;
        }

        update();
    }

    void idleCallback() final
    {
        update();
    }

    void update()
    {
        fCopy->setChecked(fInterface->isCopyingSnapshot(), false);

        const uint8_t snapshot = fInterface->getCurrentSnapshot();
        fA->setChecked(snapshot == 0, false);
        fB->setChecked(snapshot == 1, false);
        fC->setChecked(snapshot == 2, false);
        fD->setChecked(snapshot == 3, false);
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBarEasyExpertGroupWidget : public LibreAudioButtonGroupWidget,
                                              private ButtonEventHandler::Callback,
                                              private IdleCallback
{
    static constexpr const char kTextEasy[] = "Easy";
    static constexpr const char kTextExpert[] = "Expert";
    std::unique_ptr<LibreAudioButtonWidget> fEasy = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerLeft, kTextEasy>>(kWidgetEasy);
    std::unique_ptr<LibreAudioButtonWidget> fExpert = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerRight, kTextExpert>>(kWidgetExpert);

public:
    explicit LibreAudioTopBarEasyExpertGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioButtonGroupWidget(parent)
    {
        done(this);

        fEasy->setCheckable(true);
        fExpert->setCheckable(true);

        update();
        addIdleCallback(this);
    }

private:
    void buttonClicked(SubWidget* const widget, int) final
    {
        switch (widget->getId())
        {
        case kWidgetEasy:
            fInterface->pageButtonClicked(LibreAudioUIWidgetInterface::kPageButtonEasy);
            break;
        case kWidgetExpert:
            fInterface->pageButtonClicked(LibreAudioUIWidgetInterface::kPageButtonExpert);
            break;
        }

        update();
    }

    void idleCallback() final
    {
        update();
    }

    void update()
    {
        const LibreAudioUIWidgetInterface::PageButton page = fInterface->getCurrentPage();
        fEasy->setChecked(page == LibreAudioUIWidgetInterface::kPageButtonEasy, false);
        fExpert->setChecked(page == LibreAudioUIWidgetInterface::kPageButtonExpert, false);
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioTopBarMenuPowerGroupWidget : public LibreAudioButtonGroupWidget,
                                             private ButtonEventHandler::Callback,
                                             private IdleCallback
{
    std::unique_ptr<LibreAudioButtonWidget> fMenu = addButton<LibreAudioImageButtonWidget<LibreAudioButtonWidget::kCornerLeft, IMAGES_MENU_PNG_DATA, IMAGES_MENU_PNG_LEN>>(kWidgetMenu);
    std::unique_ptr<LibreAudioButtonWidget> fPower = addButton<LibreAudioBypassButtonWidget<LibreAudioButtonWidget::kCornerRight>>(kWidgetPower);

public:
    explicit LibreAudioTopBarMenuPowerGroupWidget(LibreAudioWidget* const parent)
        : LibreAudioButtonGroupWidget(parent)
    {
        done(this);

        fMenu->setCheckable(true);
        fPower->setCheckable(true);

        addIdleCallback(this);
    }

private:
    void buttonClicked(SubWidget* const widget, int) final
    {
        switch (widget->getId())
        {
        case kWidgetMenu:
            fInterface->pageButtonClicked(LibreAudioUIWidgetInterface::kPageButtonSettings);
            break;
        case kWidgetPower:
            fInterface->parameterControlPressed(kCommonParameterBypass);
            fInterface->parameterControlModified(
                kCommonParameterBypass, static_cast<LibreAudioButtonWidget*>(widget)->isChecked() ? 1.f : 0.f);
            fInterface->parameterControlReleased(kCommonParameterBypass);
            break;
        }

        update();
    }

    void idleCallback() final
    {
        update();
    }

    void update()
    {
        fMenu->setChecked(fInterface->getCurrentPage() == LibreAudioUIWidgetInterface::kPageButtonSettings, false);
        // NOTE this only triggers updates if the value doesnt match
        fPower->setChecked(d_isNotZero(fInterface->getParameterValue(kCommonParameterBypass)), false);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
