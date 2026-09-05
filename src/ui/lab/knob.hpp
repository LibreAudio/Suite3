// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "base.hpp"
#include "interface.hpp"

#include "EventHandlers.hpp"

#include "FaustParameters.hpp"

START_NAMESPACE_DGL

// --------------------------------------------------------------------------------------------------------------------

class LabKnobWidget : public LabWidget,
                      public KnobEventHandler,
                      protected IdleCallback,
                      private KnobEventHandler::Callback
{
    static constexpr const float kMouseDeceleration = 500.f;

public:
    explicit LabKnobWidget(LabWidget* const parent, const FaustParameter& parameter, const uint32_t id)
        : LabWidget(parent),
          KnobEventHandler(this),
          fParameter(parameter)
    {
        setId(id);
        setName(parameter.label);
        setCallback(this);
        setDefault(parameter.init);
        setMouseDeceleration(kMouseDeceleration);
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
        return Widget::onMouse(ev);
    }

    bool onMotion(const Widget::MotionEvent& ev) final
    {
        if (motionEvent(ev, fScaleFactor))
            return true;
        return Widget::onMotion(ev);
    }

    bool onScroll(const Widget::ScrollEvent& ev) final
    {
        if (scrollEvent(ev))
            return true;
        return Widget::onScroll(ev);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
