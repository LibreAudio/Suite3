// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "knob-group.hpp"
#include "pill-toggle.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioEasyStageWidget final : public LibreAudioReferenceContainerWidget<LibreAudioReference::Stage, kVertical>
{
    using R = LibreAudioReference::Stage;

    std::unique_ptr<LibreAudioWidget> fSpacer1 = addSpacer();
    std::unique_ptr<LibreAudioEasyKnobsGroupWidget> fEasyKnobs = addWidget<LibreAudioEasyKnobsGroupWidget>();
    std::unique_ptr<LibreAudioWidget> fSpacer2 = addSpacer();

public:
    explicit LibreAudioEasyStageWidget(LibreAudioWidget* const parent)
        : LibreAudioReferenceContainerWidget(parent)
    {
    }

private:
    void onNanoDisplay() final
    {
        const float w = getWidth();
        const float h = getHeight();

        // ------------------------------------------------------------------------------------------------------------
        // draw background and border

        beginPath();

        if constexpr (R::borderRadius != 0)
            roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
        else
            rect(0, 0, w, h);

        if constexpr (d_isNotZero(R::backgroundColor.alpha))
        {
            fillColor(R::backgroundColor);
            fill();
        }

        fillPaint(linearGradient(0, h - h * 0.4f, 0, h - h * 0.2f, LibreAudioReference::Colors::transparent, Color(0.f, 0.f, 0.f, 0.75f)));
        fill();

        if constexpr (R::border != 0 && d_isNotZero(R::borderColor.alpha))
        {
            strokeColor(R::borderColor);
            strokeWidth(R::border * 2 * fScaleFactor);
            stroke();
        }
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioExpertStageWidget final : public LibreAudioReferenceContainerWidget<LibreAudioReference::Stage, kVertical>
{
    using R = LibreAudioReference::Stage;

    std::unique_ptr<LibreAudioPillAreaWidget> fTopArea = addWidget<LibreAudioPillAreaWidget>();
    std::unique_ptr<LibreAudioWidget> fSpacer = addSpacer();
    std::unique_ptr<LibreAudioExpertKnobsGroupWidget> fExpertKnobs = addWidget<LibreAudioExpertKnobsGroupWidget>();

public:
    explicit LibreAudioExpertStageWidget(LibreAudioWidget* const parent)
        : LibreAudioReferenceContainerWidget(parent)
    {
        fTopArea->setHeight(30 * fScaleFactor);
    }

private:
    void onNanoDisplay() final
    {
        const float w = getWidth();
        const float h = getHeight();

        // ------------------------------------------------------------------------------------------------------------
        // draw background and border

        beginPath();

        if constexpr (R::borderRadius != 0)
            roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
        else
            rect(0, 0, w, h);

        if constexpr (d_isNotZero(R::backgroundColor.alpha))
        {
            fillColor(R::backgroundColor);
            fill();
        }

        fillPaint(linearGradient(0, h - h * 0.4f, 0, h - h * 0.2f, LibreAudioReference::Colors::transparent, Color(0.f, 0.f, 0.f, 0.75f)));
        fill();

        if constexpr (R::border != 0 && d_isNotZero(R::borderColor.alpha))
        {
            strokeColor(R::borderColor);
            strokeWidth(R::border * 2 * fScaleFactor);
            stroke();
        }
    }
};

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioStageWidget final : public LibreAudioWidget,
                                    private IdleCallback
{
    using R = LibreAudioReference::Stage;

    std::unique_ptr<LibreAudioWidget> fEasy { new LibreAudioEasyStageWidget(this) };
    std::unique_ptr<LibreAudioWidget> fExpert;
    // = { new LibreAudioExpertStageWidget(this) };

    LibreAudioUIWidgetInterface::PageButton fLastButton = LibreAudioUIWidgetInterface::kPageButtonEasy;

public:
    LibreAudioStageWidget(LibreAudioWidget* const parent)
        : LibreAudioWidget(parent)
    {
        fExpert.reset(new LibreAudioExpertStageWidget(this));
        fExpert->hide();

        addIdleCallback(this);
    }

private:
    void idleCallback() final
    {
        const LibreAudioUIWidgetInterface::PageButton button = fInterface->getCurrentPage();
        if (fLastButton == button)
            return;
        fLastButton = button;

        fEasy->hide();
        fExpert->hide();

        switch (button)
        {
        case LibreAudioUIWidgetInterface::kPageButtonAbout:
            break;
        case LibreAudioUIWidgetInterface::kPageButtonEasy:
            fEasy->show();
            break;
        case LibreAudioUIWidgetInterface::kPageButtonExpert:
            fExpert->show();
            break;
        case LibreAudioUIWidgetInterface::kPageButtonSettings:
            break;
        }
    }

    void onNanoDisplay() final
    {
    }

    void onPositionChanged(const PositionChangedEvent& ev) override
    {
        LibreAudioWidget::onPositionChanged(ev);

        fEasy->setAbsolutePos(ev.pos);
        fExpert->setAbsolutePos(ev.pos);
    }

    void onResize(const ResizeEvent& ev) override
    {
        LibreAudioWidget::onResize(ev);

        fEasy->setSize(ev.size);
        fExpert->setSize(ev.size);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
