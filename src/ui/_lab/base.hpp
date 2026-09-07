// lab: Libre Audio Base-Widgets
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: ISC

#pragma once

#include "Application.hpp"
#include "NanoVG.hpp"

START_NAMESPACE_DGL

class LabUIWidgetInterface;

// --------------------------------------------------------------------------------------------------------------------

enum Corner : uint8_t {
    kCornerNone,
    kCornerLeft,
    kCornerRight,
    kCornerBoth,
};

enum Orientation : bool {
    kHorizontal,
    kVertical,
};

constexpr inline const Corner kCornerAuto = static_cast<Corner>(UINT8_MAX);

// --------------------------------------------------------------------------------------------------------------------
// base widget class

template <class BaseWidget>
class BaseWidgetOf : public BaseWidget
{
public:
    explicit BaseWidgetOf(BaseWidgetOf<NanoSubWidget>* const parent)
        : BaseWidget(parent),
          fInterface(parent->fInterface),
          fScaleFactor(parent->fScaleFactor) {}

    explicit BaseWidgetOf(BaseWidgetOf<NanoTopLevelWidget>* const parent)
        : BaseWidget(parent),
          fInterface(parent->fInterface),
          fScaleFactor(parent->fScaleFactor) {}

    explicit BaseWidgetOf(Window& windowToMapTo, LabUIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo),
          fInterface(iface),
          fScaleFactor(windowToMapTo.getScaleFactor()) {}

    ~BaseWidgetOf() override
    {
        for (IdleCallback* callback : fCallbacks)
        {
            if constexpr (std::is_same_v<BaseWidget, NanoSubWidget>)
                BaseWidget::getWindow().removeIdleCallback(callback);
            else
                BaseWidget::removeIdleCallback(callback);
        }
    }

    void addIdleCallback(IdleCallback* const callback)
    {
        fCallbacks.push_back(callback);

        if constexpr (std::is_same_v<BaseWidget, NanoSubWidget>)
            BaseWidget::getWindow().addIdleCallback(callback);
        else
            BaseWidget::addIdleCallback(callback);
    }

    [[nodiscard]] double getTime() const
    {
        return BaseWidget::getApp().getTime();
    }

    [[nodiscard]] bool timeEllapsed(const double lastTime, const double wantedTime, const double timeNow) const noexcept
    {
        return d_isNotZero(lastTime) ? timeNow - lastTime >= wantedTime : false;
    }

    [[nodiscard]] bool timeEllapsed(const double lastTime, const double wantedTime) const
    {
        return timeEllapsed(lastTime, wantedTime, getTime());
    }

    [[nodiscard]] bool timeNotEllapsed(const double lastTime, const double wantedTime, const double timeNow) const noexcept
    {
        return d_isNotZero(lastTime) ? timeNow - lastTime < wantedTime : false;
    }

    [[nodiscard]] bool timeNotEllapsed(const double lastTime, const double wantedTime) const
    {
        return timeNotEllapsed(lastTime, wantedTime, getTime());
    }

protected:
    LabUIWidgetInterface* const fInterface;
    float fScaleFactor;

    [[nodiscard]] virtual const Color& getBackgroundColor() const noexcept
    {
        __builtin_unreachable();
    }

    [[nodiscard]] virtual const Color& getBorderColor() const noexcept
    {
        __builtin_unreachable();
    }

    [[nodiscard]] virtual Corner getCorner() const noexcept
    {
        __builtin_unreachable();
    }

    template <class R, Corner _corner = kCornerAuto>
    void drawReferenceBackground()
    {
        constexpr Corner corner = _corner != kCornerAuto ? _corner : R::borderRadius != 0 ? kCornerBoth : kCornerNone;
       #ifdef __GNUC__
        #pragma GCC poison _corner
       #endif
        static_assert(corner == kCornerNone || R::borderRadius != 0, "corner != none requires borderRadius");

        const float w = BaseWidget::getWidth();
        const float h = BaseWidget::getHeight();

        {
            const Color& backgroundColor = this->getBackgroundColor();

            BaseWidget::beginPath();

            if constexpr (R::borderRadius != 0 && corner != kCornerNone)
                BaseWidget::roundedRect(0, 0, w, h, R::borderRadius * fScaleFactor);
            else
                BaseWidget::rect(0, 0, w, h);

            if /*constexpr*/ (d_isNotZero(backgroundColor.alpha))
            {
                if constexpr (corner == kCornerLeft || corner == kCornerRight)
                {
                    DISTRHO_CUSTOM_SAFE_ASSERT_RETURN("Corners must have opaque color",
                                                      d_isEqual(R::backgroundColor.alpha, 1.f),);
                }

                BaseWidget::fillColor(backgroundColor);
                BaseWidget::fill();

                if constexpr (corner == kCornerLeft)
                {
                    BaseWidget::beginPath();
                    BaseWidget::rect(w * 0.5f, 0, w * 0.5f, h);
                    BaseWidget::fill();
                }
                if constexpr (corner == kCornerRight)
                {
                    BaseWidget::beginPath();
                    BaseWidget::rect(0, 0, w * 0.5f, h);
                    BaseWidget::fill();
                }
            }
        }

        if constexpr (R::border != 0)
        {
            const Color& borderColor = this->getBorderColor();

            if /*constexpr*/ (d_isNotZero(borderColor.alpha))
            {
                const float border = d_roundToIntPositive(R::border * fScaleFactor);
                const float borderh = border * 0.5f;

                const float sx = borderh;
                const float sy = borderh;
                const float ex = w - borderh;
                const float ey = h - borderh;

                BaseWidget::beginPath();

                if constexpr (R::borderRadius != 0)
                {
                    const float borderRadius = R::borderRadius * fScaleFactor;
                    DISTRHO_SAFE_ASSERT_RETURN(borderRadius < w * 0.5f,);
                    DISTRHO_SAFE_ASSERT_RETURN(borderRadius < h * 0.5f,);
                    DISTRHO_SAFE_ASSERT_RETURN(borderRadius > border,);

                    const float arcRadius = borderRadius - border;

                    BaseWidget::moveTo(sx + borderRadius, sy);
                    BaseWidget::arcTo(sx, sy, sx, ey - borderRadius, arcRadius);
                    BaseWidget::lineTo(sx, ey - borderRadius);
                    BaseWidget::arcTo(sx, ey, sx + borderRadius, ey, arcRadius);
                    BaseWidget::lineTo(ex - borderRadius, ey);
                    BaseWidget::arcTo(ex, ey, ex, ey - borderRadius, arcRadius);
                    BaseWidget::lineTo(ex, sx + borderRadius);
                    BaseWidget::arcTo(ex, sy, ex - borderRadius, sy, arcRadius);
                }
                else
                {
                    BaseWidget::moveTo(sx, sy);
                    BaseWidget::lineTo(sx, ey);
                    BaseWidget::lineTo(ex, ey);
                    BaseWidget::lineTo(ex, sy);
                }

                BaseWidget::closePath();
                BaseWidget::strokeColor(borderColor);
                BaseWidget::strokeWidth(border);
                BaseWidget::stroke();
            }
        }
    }

    template <class R>
    void updateReferenceSize()
    {
        if constexpr (R::width != 0)
            BaseWidget::setWidth(d_roundToUnsignedInt(R::width * fScaleFactor));

        if constexpr (R::height != 0)
            BaseWidget::setHeight(d_roundToUnsignedInt(R::height * fScaleFactor));
    }

    void updateScaleFactor(const float scaleFactor)
    {
        fScaleFactor = scaleFactor;

        const std::list<SubWidget*> children = BaseWidget::getChildren();

        for (SubWidget* const child : children)
            static_cast<BaseWidgetOf<NanoSubWidget>*>(child)->updateScaleFactor(scaleFactor);
    }

    virtual void updateSize(const bool updateChildren = true)
    {
        if (! updateChildren)
            return;

        const std::list<SubWidget*> children = BaseWidget::getChildren();

        for (SubWidget* const child : children)
            static_cast<BaseWidgetOf<NanoSubWidget>*>(child)->updateSize(true);
    }

private:
    // FIXME remove this
    std::vector<IdleCallback*> fCallbacks;

    friend class BaseWidgetOf<NanoSubWidget>;
    friend class BaseWidgetOf<NanoTopLevelWidget>;
};

// --------------------------------------------------------------------------------------------------------------------
// top-level widget class

class LabTopLevelWidget : public BaseWidgetOf<NanoTopLevelWidget>
{
    using BaseWidget = BaseWidgetOf<NanoTopLevelWidget>;

public:
    explicit LabTopLevelWidget(Window& windowToMapTo, LabUIWidgetInterface* const iface)
        : BaseWidget(windowToMapTo, iface) {}

    void setWidth() = delete;
    void setHeight() = delete;
    void setSize() = delete;

protected:
    void onNanoDisplay() override
    {
    }
};

// --------------------------------------------------------------------------------------------------------------------
// (sub) widget class

class LabWidget : public BaseWidgetOf<NanoSubWidget>
{
    using BaseWidget = BaseWidgetOf<NanoSubWidget>;

public:
    explicit LabWidget(LabTopLevelWidget* const parent)
        : BaseWidget(parent) {}

    explicit LabWidget(LabWidget* const parent)
        : BaseWidget(parent) {}
};

// --------------------------------------------------------------------------------------------------------------------
// do not allow using `BaseWidgetOf` after this point

#ifdef __GNUC__
#pragma GCC poison BaseWidgetOf
#endif

// --------------------------------------------------------------------------------------------------------------------
// reference (sub) widget class

template<class R, Corner corner = kCornerAuto>
class LabReferenceWidget : public LabWidget
{
    using BaseWidget = LabWidget;

public:
    explicit LabReferenceWidget(LabTopLevelWidget* const parent)
        : BaseWidget(parent)
    {
        updateReferenceSize<R>();
    }

    explicit LabReferenceWidget(LabWidget* const parent)
        : BaseWidget(parent)
    {
        updateReferenceSize<R>();
    }

protected:
    [[nodiscard]] const Color& getBackgroundColor() const noexcept override
    {
        return R::backgroundColor;
    }

    [[nodiscard]] const Color& getBorderColor() const noexcept override
    {
        return R::borderColor;
    }

    [[nodiscard]] Corner getCorner() const noexcept override
    {
        return corner;
    }

    void onNanoDisplay() override
    {
        drawReferenceBackground<R, corner>();
    }

    void updateSize(const bool updateChildren) override
    {
        updateReferenceSize<R>();
        BaseWidget::updateSize(updateChildren);
    }
};

// --------------------------------------------------------------------------------------------------------------------

END_NAMESPACE_DGL
