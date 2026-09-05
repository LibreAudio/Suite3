// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../widgets/base.hpp"
#include "knob-group.hpp"
#include "pill-toggle.hpp"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class EasyStageWidget final : public ReferenceContainerWidget<Reference::Stage, kVertical>
{
    using R = Reference::Stage;
    using BaseWidget = ReferenceContainerWidget<R, kVertical>;

    std::shared_ptr<Widget> fSpacer1 = addSpacer();
    std::shared_ptr<EasyKnobsGroupWidget> fEasyKnobs = addWidget<EasyKnobsGroupWidget>();
    std::shared_ptr<Widget> fSpacer2 = addSpacer();

public:
    explicit EasyStageWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
    }

private:
    void onNanoDisplay() final
    {
        drawReferenceBackground<R>();

        const float w = getWidth();
        const float h = getHeight();

        // TODO move to layer 2

        beginPath();

        if constexpr (R::borderRadius != 0)
            roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
        else
            rect(0, 0, w, h);

        fillPaint(linearGradient(0,
                                 h - h * 0.4f,
                                 0,
                                 h - h * 0.2f,
                                 Reference::Colors::transparent,
                                 Color(0.f, 0.f, 0.f, 0.2f)));
        fill();
    }
};

// --------------------------------------------------------------------------------------------------------------------

class ExpertStageWidget final : public ReferenceContainerWidget<Reference::Stage, kVertical>
{
    using R = Reference::Stage;
    using BaseWidget = ReferenceContainerWidget<R, kVertical>;

    std::shared_ptr<PillAreaWidget> fTopArea = addWidget<PillAreaWidget>();
    std::shared_ptr<Widget> fSpacer = addSpacer();
    std::shared_ptr<ExpertKnobsGroupWidget> fExpertKnobs = addWidget<ExpertKnobsGroupWidget>();

public:
    explicit ExpertStageWidget(LabWidget* const parent)
        : BaseWidget(parent)
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

        fillPaint(linearGradient(0, h - h * 0.4f, 0, h - h * 0.2f, Reference::Colors::transparent, Color(0.f, 0.f, 0.f, 0.2f)));
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

class StageWidget final : public LabWidget,
                          private IdleCallback
{
    using R = Reference::Stage;
    using BaseWidget = LabWidget;

    std::shared_ptr<LabWidget> fEasy { new EasyStageWidget(this) };
    std::shared_ptr<LabWidget> fExpert;
    // = { new ExpertStageWidget(this) };

    Page fLastPage = kPageEasy;

public:
    StageWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        fExpert.reset(new ExpertStageWidget(this));
        fExpert->hide();

        addIdleCallback(this);
    }

    [[nodiscard]] float getBorderRadius() const noexcept
    {
        return R::borderRadius * fScaleFactor;
    }

private:
    void idleCallback() final
    {
        const Page page = getCurrentPage(fInterface);
        if (fLastPage == page)
            return;
        fLastPage = page;

        fEasy->hide();
        fExpert->hide();

        switch (page)
        {
        case kPageAbout:
            break;
        case kPageEasy:
            fEasy->show();
            break;
        case kPageExpert:
            fExpert->show();
            break;
        case kPageSettings:
            break;
        }
    }

    void onNanoDisplay() final
    {
    }

    void onPositionChanged(const PositionChangedEvent& ev) override
    {
        BaseWidget::onPositionChanged(ev);

        fEasy->setAbsolutePos(ev.pos);
        fExpert->setAbsolutePos(ev.pos);
    }

    // void onResize(const ResizeEvent& ev) override
    // {
    //     Widget::onResize(ev);
    //
    //     fEasy->setSize(ev.size);
    //     fExpert->setSize(ev.size);
    // }

    void updateSize(const bool updateChildren) override
    {
        fEasy->setSize(getSize());
        fExpert->setSize(getSize());

        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

} /* namespace LibreAudio */
