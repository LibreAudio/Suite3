// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "reference/image.hpp"
#include "base/interface.hpp"
#include "reference/button-group.hpp"
#include "widgets-todo/base.hpp"
#include "widgets-todo/button.hpp"
// #include "widgets/knob.hpp"
// #include "widgets/knob-group.hpp"
// #include "widgets/line.hpp"
// #include "widgets/meter.hpp"
// #include "widgets/pill-toggle.hpp"
// #include "widgets/shader.hpp"
// #include "widgets/stage.hpp"
// #include "widgets/top-bar-name.hpp"
// #include "LibreAudioParameters.hpp"

#include "las-resources.h"

START_NAMESPACE_DISTRHO

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
        fInterface->buttonClicked(widget->getId());
        update();
    }

    void idleCallback() final
    {
        update();
    }

    void update()
    {
        fUndo->setEnabled(fInterface->isButtonEnabled(kWidgetUndo));
        fRedo->setEnabled(fInterface->isButtonEnabled(kWidgetRedo));
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
    std::unique_ptr<LibreAudioButtonWidget> fA = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerNone, kTextA>>(kWidgetSnapshotSlotA);
    std::unique_ptr<LibreAudioButtonWidget> fB = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerNone, kTextB>>(kWidgetSnapshotSlotB);
    std::unique_ptr<LibreAudioButtonWidget> fC = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerNone, kTextC>>(kWidgetSnapshotSlotC);
    std::unique_ptr<LibreAudioButtonWidget> fD = addButton<LibreAudioStaticTextButtonWidget<LibreAudioButtonWidget::kCornerRight, kTextD>>(kWidgetSnapshotSlotD);

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
        fInterface->buttonClicked(widget->getId());
        update();
    }

    void idleCallback() final
    {
        update();
    }

    void update()
    {
        fCopy->setChecked(fInterface->isButtonChecked(kWidgetSnapshotCopy), false);
        fA->setChecked(fInterface->isButtonChecked(kWidgetSnapshotSlotA), false);
        fB->setChecked(fInterface->isButtonChecked(kWidgetSnapshotSlotB), false);
        fC->setChecked(fInterface->isButtonChecked(kWidgetSnapshotSlotC), false);
        fD->setChecked(fInterface->isButtonChecked(kWidgetSnapshotSlotD), false);
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
        fInterface->buttonClicked(widget->getId());
        update();
    }

    void idleCallback() final
    {
        update();
    }

    void update()
    {
        fEasy->setChecked(fInterface->isButtonChecked(kWidgetEasy), false);
        fExpert->setChecked(fInterface->isButtonChecked(kWidgetExpert), false);
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
        fInterface->buttonClicked(widget->getId());
        update();
    }

    void idleCallback() final
    {
        update();
    }

    void update()
    {
        fMenu->setChecked(fInterface->isButtonChecked(kWidgetMenu), false);
        fPower->setChecked(fInterface->isButtonChecked(kWidgetPower), false);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
