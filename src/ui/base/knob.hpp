// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "base.hpp"
#include "interface.hpp"

#include "EventHandlers.hpp"

#include "FaustParameters.hpp"

START_NAMESPACE_DISTRHO

// --------------------------------------------------------------------------------------------------------------------

class LibreAudioKnobWidget : public LibreAudioWidget,
                             public KnobEventHandler,
                             protected IdleCallback,
                             private KnobEventHandler::Callback
{
public:
    explicit LibreAudioKnobWidget(LibreAudioWidget* const parent, const FaustParameter& parameter, const uint32_t id)
        : LibreAudioWidget(parent),
          KnobEventHandler(this),
          fParameter(parameter)
    {
        setId(id);
        setName(parameter.label);
        setCallback(this);
        setDefault(parameter.init);
        setMouseDeceleration(500.f);
        setOrientation(Vertical);
        setRange(parameter.min, parameter.max);
        setStep(parameter.step);
        // setUsingLogScale(parameter.isLogarithmic); // FIXME
        setValue(parameter.init, false);

        addIdleCallback(this);
    }

protected:
    const FaustParameter& fParameter;

    void idleCallback() override
    {
        // NOTE this only triggers updates if the value doesnt match
        if (setValue(fInterface->getParameterValue(getId())))
            parameterChangedByHost();
    }

    virtual void parameterChangedByHost()
    {
    }

private:
    void knobDragStarted(SubWidget* const widget) final
    {
        fInterface->parameterControlPressed(widget->getId());
    }

    void knobDragFinished(SubWidget* const widget) final
    {
        fInterface->parameterControlReleased(widget->getId());
    }

    void knobValueChanged(SubWidget* const widget, const float value) final
    {
        fInterface->parameterControlModified(widget->getId(), value);
    }

    void knobDoubleClicked(SubWidget*) final
    {
    }

    bool onMouse(const Widget::MouseEvent& ev) final
    {
        if (mouseEvent(ev, fScaleFactor))
            return true;
        return LibreAudioWidget::onMouse(ev);
    }

    bool onMotion(const Widget::MotionEvent& ev) final
    {
        if (motionEvent(ev, fScaleFactor))
            return true;
        return LibreAudioWidget::onMotion(ev);
    }

    bool onScroll(const Widget::ScrollEvent& ev) final
    {
        if (scrollEvent(ev))
            return true;
        return LibreAudioWidget::onScroll(ev);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
