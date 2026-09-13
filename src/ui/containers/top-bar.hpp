// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "../_lab/image.hpp"
#include "../_lab/interface.hpp"

#include "../widgets/button.hpp"
#include "../widgets/button-group.hpp"
#include "../widgets/plugin-name.hpp"

#include <array>

#include "las-resources.h"

namespace LibreAudio {

// --------------------------------------------------------------------------------------------------------------------

class TopBar : public ReferenceContainerWidget<Reference::TopBar>,
               private IdleCallback
{
    using BaseWidget = ReferenceContainerWidget<Reference::TopBar>;

    // ----------------------------------------------------------------------------------------------------------------

    using LogoWidget = LabImageWidget<IMAGES_LA_PNG_DATA, IMAGES_LA_PNG_LEN>;

    // ----------------------------------------------------------------------------------------------------------------

    class UndoRedoGroupWidget : public ButtonGroupWidget
    {
        using UndoButtonWidget = ImageButtonWidget<kCornerLeft, IMAGES_UNDO_PNG_DATA, IMAGES_UNDO_PNG_LEN>;
        using RedoButtonWidget = ImageButtonWidget<kCornerRight, IMAGES_REDO_PNG_DATA, IMAGES_REDO_PNG_LEN>;

    public:
        explicit UndoRedoGroupWidget(LabWidget* const parent)
            : ButtonGroupWidget(parent)
        {
            addButton<UndoButtonWidget>(kWidgetUndo);
            addButton<RedoButtonWidget>(kWidgetRedo);
            done();
        }
    };

    // ----------------------------------------------------------------------------------------------------------------

    class SnapshotsGroupWidget : public ButtonGroupWidget
    {
        using SnapshotCopyButtonWidget = DualImageButtonWidget<
            kCornerLeft, IMAGES_X_PNG_DATA, IMAGES_X_PNG_LEN, IMAGES_COPY_PNG_DATA, IMAGES_COPY_PNG_LEN>;

    public:
        explicit SnapshotsGroupWidget(LabWidget* const parent)
            : ButtonGroupWidget(parent)
        {
            addButton<SnapshotCopyButtonWidget>(kWidgetSnapshotCopy);
            addButton<TextButtonWidget<kCornerNone>>(kWidgetSnapshotSlotA, "A");
            addButton<TextButtonWidget<kCornerNone>>(kWidgetSnapshotSlotB, "B");
            addButton<TextButtonWidget<kCornerNone>>(kWidgetSnapshotSlotC, "C");
            addButton<TextButtonWidget<kCornerRight>>(kWidgetSnapshotSlotD, "D");
            done();
        }
    };

    // ----------------------------------------------------------------------------------------------------------------

    class EasyExpertGroupWidget : public ButtonGroupWidget
    {
    public:
        explicit EasyExpertGroupWidget(LabWidget* const parent)
            : ButtonGroupWidget(parent)
        {
            addButton<TextButtonWidget<kCornerLeft>>(kWidgetEasy, "Easy");
            addButton<TextButtonWidget<kCornerRight>>(kWidgetExpert, "Expert");
            done();
        }
    };

    // ----------------------------------------------------------------------------------------------------------------

    class MenuPowerGroupWidget : public ButtonGroupWidget
    {
        using MenuButtonWidget = ImageButtonWidget<kCornerLeft, IMAGES_MENU_PNG_DATA, IMAGES_MENU_PNG_LEN>;

    public:
        explicit MenuPowerGroupWidget(LabWidget* const parent)
            : ButtonGroupWidget(parent)
        {
            addButton<MenuButtonWidget>(kWidgetMenu);
            addButton<BypassButtonWidget<kCornerRight>>(kWidgetPower);
            done();
        }
    };

    // ----------------------------------------------------------------------------------------------------------------

    const std::array<std::shared_ptr<LabWidget>, 3> fWidgetsLeft = {
        addWidget<LogoWidget>(),
        addWidget<PluginNameWidget>(),
        addSpacer(),
    };
    const std::array<std::shared_ptr<LabWidget>, 2> fWidgetsExpert = {
        addWidget<UndoRedoGroupWidget>(),
        addWidget<SnapshotsGroupWidget>(),
    };
    const std::array<std::shared_ptr<LabWidget>, 2> fWidgetsRight = {
        addWidget<EasyExpertGroupWidget>(),
        addWidget<MenuPowerGroupWidget>()
    };

    // ----------------------------------------------------------------------------------------------------------------

public:
    TopBar(LabTopLevelWidget* const parent)
        : BaseWidget(parent)
    {
        updateSize(true);
        idleCallback();

        addIdleCallback(this);
    }

private:
    Page fLastPage = kPageInit;

    void idleCallback() final
    {
        if (const Page page = getCurrentPage(fInterface); fLastPage != page)
        {
            switch (page)
            {
            case kPageAbout:
            case kPageSettings:
                if (fLastPage != kPageInit)
                    break;
                [[fallthrough]];

            case kPageEasy:
            case kPageExpert:
                for (const std::shared_ptr<LabWidget>& widget : fWidgetsExpert)
                    widget->setVisible(page == kPageExpert);

                if (fLastPage != kPageInit)
                    updateSize(true);

                fLastPage = page;
                break;
            }
        }
    }
};

// --------------------------------------------------------------------------------------------------------------------

}
