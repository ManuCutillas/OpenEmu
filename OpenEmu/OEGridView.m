/*
 Copyright (c) 2012, OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "OEGridView.h"

#import "OETheme.h"

#import <QuickLook/QuickLook.h>

#import "OEGridGameCell.h"
#import "OEGridViewFieldEditor.h"
#import "OEBackgroundNoisePattern.h"
#import "OECoverGridDataSourceItem.h"

#import "OEMenu.h"

#pragma mark - ImageKit Private Headers
#import "IKImageBrowserView.h"
#import "IKImageWrapper.h"
#import "IKRenderer.h"
#import "IKImageBrowserLayoutManager.h"
#import "IKImageBrowserGridGroup.h"

#pragma mark -
NSSize const defaultGridSize = (NSSize){26+142, 143};
NSString *const OEImageBrowserGroupSubtitleKey = @"OEImageBrowserGroupSubtitleKey";
NSString *const OECoverGridViewGlossDisabledKey = @"OECoverGridViewGlossDisabledKey";

@interface NSView (ApplePrivate)
- (void)setClipsToBounds:(BOOL)arg1;
@end
// TODO: replace OEDBGame with OECoverGridDataSourceItem
@interface OEGridView ()
@property NSDraggingSession *draggingSession;
@property NSPoint           lastPointInView;
@property NSInteger draggingIndex;
@property NSInteger editingIndex;
@property NSInteger ratingTracking;
@property OEGridViewFieldEditor *fieldEditor;

@property CALayer *dragIndicationLayer;

// Theme Objects
@property (strong) OEThemeImage          *groupBackgroundImage;
@property (strong) OEThemeTextAttributes *groupTitleAttributes;
@property (strong) OEThemeTextAttributes *groupSubtitleAttributes;
@end

@implementation OEGridView
static IKImageWrapper *lightingImage, *noiseImageHighRes, *noiseImage;
+ (void)initialize
{
    if([self class] != [OEGridView class])
        return;


    NSImage *nslightingImage = [NSImage imageNamed:@"background_lighting"];
    lightingImage = [IKImageWrapper imageWithNSImage:nslightingImage];

    OEBackgroundNoisePatternCreate();
    OEBackgroundHighResolutionNoisePatternCreate();

    noiseImage = [IKImageWrapper imageWithCGImage:OEBackgroundNoiseImageRef];
    noiseImageHighRes = [IKImageWrapper imageWithCGImage:OEBackgroundHighResolutionNoiseImageRef];
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _cellClass = [IKImageBrowserCell class];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self)
    {
        _cellClass = [IKImageBrowserCell class];
        [self performSetup];
    }
    return self;
}

- (void)awakeFromNib
{
    [self performSetup];
}

- (void)performSetup
{
    _editingIndex = NSNotFound;
    _ratingTracking = NSNotFound;

    if([self groupThemeKey] == nil)
    {
        [self setGroupThemeKey:@"grid_group"];
    }

    [self registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, NSPasteboardTypePNG, NSPasteboardTypeTIFF, nil]];
    [self setAllowsReordering:NO];
    [self setAllowsDroppingOnItems:YES];
    [self setAnimates:NO];

    [self private_setClipsToBounds:NO];
    [self setCellsStyleMask:IKCellsStyleNone];

    IKImageBrowserLayoutManager *layoutManager = [self layoutManager];

    [layoutManager setCellMargin:CGSizeMake(35, 35)];
    [layoutManager setMargin:CGSizeMake(0, 35)];
    [layoutManager setAlignLeftForSingleRow:NO];
    [layoutManager setAutomaticallyMinimizeRowMargin:NO];

    _fieldEditor = [[OEGridViewFieldEditor alloc] initWithFrame:NSMakeRect(50, 50, 50, 50)];
    [self addSubview:_fieldEditor];
}

- (void)setGroupThemeKey:(NSString*)key
{
    OETheme *theme = [OETheme sharedTheme];

    _groupThemeKey = key;

    NSString *backgroundImageKey = [key stringByAppendingString:@"_background"];
    [self setGroupBackgroundImage:[theme themeImageForKey:backgroundImageKey]];

    NSString *titleAttributesKey = [key stringByAppendingString:@"_title"];
    [self setGroupTitleAttributes:[theme themeTextAttributesForKey:titleAttributesKey]];

    NSString *subtitleAttributesKey = [key stringByAppendingString:@"_subtitle"];
    [self setGroupSubtitleAttributes:[theme themeTextAttributesForKey:subtitleAttributesKey]];
}
#pragma mark - Cells
- (IKImageBrowserCell *)newCellForRepresentedItem:(id) cell
{
	return [[[self cellClass] alloc] init];
}
#pragma mark -
- (NSInteger)indexOfItemWithFrameAtPoint:(NSPoint)point
{
    __block NSInteger result = NSNotFound;
    [[self visibleItemIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSRect frame = [self itemFrameAtIndex:idx];
        if(NSPointInRect(point, frame))
        {
            result = idx;
            *stop = YES;
        }
    }];
    return result;
}
#pragma mark - Controlling Layout
- (void)setAutomaticallyMinimizeRowMargin:(BOOL)flag
{
    [[self layoutManager] setAutomaticallyMinimizeRowMargin:flag];
}
- (BOOL)automaticallyMinimizeRowMargin
{
    return [[self layoutManager] automaticallyMinimizeRowMargin];
}
#pragma mark - ToolTips
- (void)installToolTips
{
    [self removeAllToolTips];
    [[self visibleItemIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        IKImageBrowserCell *cell = [self cellForItemAtIndex:idx];
        NSRect titleRect = [cell titleFrame];
        [self addToolTipRect:titleRect owner:self userData:(void *)idx];
    }];
}

- (NSString*)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data
{
    NSUInteger idx = (NSUInteger)data;
    id obj = [[self dataSource] imageBrowser:self itemAtIndex:idx];
    return [obj imageTitle];
}
#pragma mark - Managing Responder
- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    BOOL success = [super becomeFirstResponder];
    [self setNeedsDisplay:YES];
    return success;
}

- (BOOL)resignFirstResponder
{
    BOOL success = [super resignFirstResponder];
    [self setNeedsDisplay:YES];
    return success;
}

#pragma mark - Mouse Interaction
- (void)mouseDown:(NSEvent *)theEvent
{
    [self OE_cancelFieldEditor];

    NSPoint mouseLocationInWindow = [theEvent locationInWindow];
    NSPoint mouseLocationInView = [self convertPoint:mouseLocationInWindow fromView:nil];
    NSInteger index = [self indexOfItemWithFrameAtPoint:mouseLocationInView];

    if(index != NSNotFound)
    {
        IKImageBrowserCell *cell = [self cellForItemAtIndex:index];

        const NSRect titleRect  = [cell titleFrame];
        const NSRect imageRect  = [cell imageFrame];
        // see if user double clicked on title layer
        if([theEvent clickCount] >= 2 && NSPointInRect(mouseLocationInView, titleRect))
        {
            [self beginEditingItemAtIndex:index];
            return;
        }
        // Check for dragging
        else if(NSPointInRect(mouseLocationInView, imageRect))
        {
            _draggingIndex = index;
        }
        else if([cell isKindOfClass:[OEGridGameCell class]])
        {
            OEGridGameCell *clickedCell = (OEGridGameCell*)cell;
            const NSRect ratingRect = NSInsetRect([clickedCell ratingFrame], -5, -1);

            // Check for rating layer interaction
            if(NSPointInRect(mouseLocationInView, ratingRect))
            {
                _ratingTracking = index;
                [self OE_updateRatingForItemAtIndex:index withLocation:mouseLocationInView inRect:ratingRect];
                return;
            }
        }
    }
    
    _lastPointInView = mouseLocationInView;

    [super mouseDown:theEvent];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    if(_draggingSession) return;

    const NSPoint mouseLocationInWindow = [theEvent locationInWindow];
    const NSPoint mouseLocationInView = [self convertPoint:mouseLocationInWindow fromView:nil];
    const NSPoint draggedDistance = NSMakePoint(ABS(mouseLocationInView.x - _lastPointInView.x), ABS(mouseLocationInView.y - _lastPointInView.y));

    if(_draggingIndex != NSNotFound && (draggedDistance.x >= 5.0 || draggedDistance.y >= 5.0 || (draggedDistance.x * draggedDistance.x + draggedDistance.y * draggedDistance.y) >= 25))
    {
        NSIndexSet *selectionIndexes = [self selectionIndexes];
        NSMutableArray *draggingItems = [NSMutableArray array];

        [selectionIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            IKImageBrowserCell *cell = [self cellForItemAtIndex:idx];
            id           item         = [cell representedItem];
            const NSRect imageRect    = [cell imageFrame];

            NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:item];
            NSImage *dragImage = nil;
            if([[item imageUID] characterAtIndex:0] == ':')
            {
                dragImage = [OEGridGameCell missingArtworkImageWithSize:imageRect.size];
            }
            else
            {
                IKImageWrapper *thumbnail = [self thumbnailImageAtIndex:idx];
                dragImage = [thumbnail nsImage];
            }

            [dragItem setDraggingFrame:imageRect contents:dragImage];
            [draggingItems addObject:dragItem];
        }];

        // If there are items being dragged, start a dragging session
        if([draggingItems count] > 0)
        {
            _draggingSession = [self beginDraggingSessionWithItems:draggingItems event:theEvent source:self];
            [_draggingSession setDraggingLeaderIndex:_draggingIndex];
            [_draggingSession setDraggingFormation:NSDraggingFormationStack];
        }

        _draggingIndex = NSNotFound;
        _lastPointInView = mouseLocationInView;
        return;
    }
    else if(_ratingTracking != NSNotFound)
    {
        OEGridGameCell *clickedCell = (OEGridGameCell*)[self cellForItemAtIndex:_ratingTracking];
        NSRect ratingRect = NSInsetRect([clickedCell ratingFrame], -5, -1);

        [self OE_updateRatingForItemAtIndex:_ratingTracking withLocation:mouseLocationInView inRect:ratingRect];
        _lastPointInView = mouseLocationInView;
        return;
    }

    [super mouseDragged:theEvent];
}

- (void)mouseUp:(NSEvent *)theEvent
{
    _ratingTracking = NSNotFound;
    _draggingIndex  = NSNotFound;

    [super mouseUp:theEvent];
}

- (id)groupAtViewLocation:(struct CGPoint)arg1 clickableArea:(BOOL)arg2
{
    // Return no group if grid view is looking for something clickable
    // this prevents it from selecting all items in a group making group
    // headers unclickable
    if(arg2) return nil;
    return [super groupAtViewLocation:arg1 clickableArea:arg2];
}

- (void)startSelectionProcess:(NSPoint)arg1
{
    // Since we disabled clickable group header image views will start
    // selecting, this should be disabled as well for clicks starting in
    // group headers
    IKImageBrowserGridGroup *group = [super groupAtViewLocation:arg1 clickableArea:YES];
    if(group == nil)
        [super startSelectionProcess:arg1];
}
#pragma mark - Keyboard Interaction
- (void)keyDown:(NSEvent*)event
{
    // original implementation does not pass space key to type-select
    if([event keyCode]==kVK_Space)
    {
        [self handleKeyInput:event character:' '];
    } else [super keyDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    [[self window] makeFirstResponder:self];

    NSPoint mouseLocationInWindow = [theEvent locationInWindow];
    NSPoint mouseLocationInView = [self convertPoint:mouseLocationInWindow fromView:nil];

    NSInteger index = [self indexOfItemAtPoint:mouseLocationInView];
    if(index != NSNotFound && [[self dataSource] respondsToSelector:@selector(gridView:menuForItemsAtIndexes:)])
    {
        BOOL            itemIsSelected      = [[self cellForItemAtIndex:index] isSelected];
        NSIndexSet     *indexes             = itemIsSelected ? [self selectionIndexes] : [NSIndexSet indexSetWithIndex:index];

        if(!itemIsSelected)
            [self setSelectionIndexes:indexes byExtendingSelection:NO];

        NSMenu *contextMenu = [(id <OEGridViewMenuSource>)[self dataSource] gridView:self menuForItemsAtIndexes:indexes];
        if(!contextMenu) return nil;

        OEMenuStyle     style      = ([[NSUserDefaults standardUserDefaults] boolForKey:OEMenuOptionsStyleKey] ? OEMenuStyleLight : OEMenuStyleDark);
        IKImageBrowserCell *itemCell   = [self cellForItemAtIndex:index];

        NSRect          hitRect             = NSInsetRect([itemCell imageFrame], 5, 5);
        //NSRect          hitRectOnView       = [itemCell convertRect:hitRect toLayer:self.layer];
        int major, minor;
        GetSystemVersion(&major, &minor, NULL);
        if (major == 10 && minor < 8) hitRect.origin.y = self.bounds.size.height - hitRect.origin.y - hitRect.size.height;
        NSRect          hitRectOnWindow     = [self convertRect:hitRect toView:nil];
        NSRect          visibleRectOnWindow = [self convertRect:[self visibleRect] toView:nil];
        NSRect          visibleItemRect     = NSIntersectionRect(hitRectOnWindow, visibleRectOnWindow);

        // we enhance the calculated rect to get a visible gap between the item and the menu
        NSRect enhancedVisibleItemRect = NSInsetRect(visibleItemRect, -3, -3);

        const NSRect  targetRect = [[self window] convertRectToScreen:enhancedVisibleItemRect];
        NSDictionary *options    = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithUnsignedInteger:style], OEMenuOptionsStyleKey,
                                    [NSNumber numberWithUnsignedInteger:OEMinXEdge], OEMenuOptionsArrowEdgeKey,
                                    [NSValue valueWithRect:targetRect], OEMenuOptionsScreenRectKey,
                                    nil];

        // Display the menu
        [[self window] makeFirstResponder:self];
        [OEMenu openMenu:contextMenu withEvent:theEvent forView:self options:options];
        return nil;
    }

    return [super menuForEvent:theEvent];
}

#pragma mark - NSDraggingSource
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    DLog();
    return context == NSDraggingContextWithinApplication ? NSDragOperationCopy : NSDragOperationNone;
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation
{
    DLog();
    _draggingSession = nil;
    _draggingIndex  = NSNotFound;
}

- (void)draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint
{}
- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint
{}
- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session
{
    return YES;
}
#pragma mark - NSDraggingDestination
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    [self OE_generateProposedImageFromPasteboard:[sender draggingPasteboard]];
    NSDragOperation op = [super draggingEntered:sender];
    return op;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    [self setProposedImage:nil];
    return [super performDragOperation:sender];
}

- (void)draggingExited:(id<NSDraggingInfo>)sender
{
    [self setProposedImage:nil];
    [super draggingExited:sender];
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
    NSDragOperation op = [super draggingUpdated:sender];
    return op;
}

- (void)draggingEnded:(id<NSDraggingInfo>)sender
{
    [self setProposedImage:nil];
    [super draggingEnded:sender];
}

- (void)OE_generateProposedImageFromPasteboard:(NSPasteboard*)pboard
{
    NSImage *image = nil;
    if([[pboard pasteboardItems] count] == 1)
    {
        image  = [[pboard readObjectsForClasses:@[[NSImage class]] options:@{}] lastObject];
        if(image == nil)
        {
            NSURL *url = [[pboard readObjectsForClasses:@[[NSURL class]] options:@{}] lastObject];
            QLThumbnailRef thumbnailRef = QLThumbnailCreate(NULL, (__bridge CFURLRef)url, [self cellSize], NULL);
            if(thumbnailRef)
            {
                CGImageRef thumbnailImageRef = QLThumbnailCopyImage(thumbnailRef);
                if(thumbnailImageRef)
                {
                    image = [[NSImage alloc] initWithCGImage:thumbnailImageRef size:NSMakeSize(CGImageGetWidth(thumbnailImageRef), CGImageGetHeight(thumbnailImageRef))];
                    CGImageRelease(thumbnailImageRef);
                }
                CFRelease(thumbnailRef);
            }
        }
    }

    [self setProposedImage:image];
}
#pragma mark - Rating items
- (void)OE_updateRatingForItemAtIndex:(NSInteger)index withLocation:(NSPoint)location inRect:(NSRect)rect
{
    CGFloat percent = (location.x - NSMinX(rect))/NSWidth(rect);
    percent = MAX(MIN(percent, 1.0), 0.0);
    [self setRating:roundf(5*percent) forGameAtIndex:index];
}

- (void)setRating:(NSInteger)rating forGameAtIndex:(NSInteger)index
{
    OEGridGameCell *selectedCell = (OEGridGameCell *)[self cellForItemAtIndex:index];
    id <OECoverGridDataSourceItem> selectedGame = [selectedCell representedItem];
    [selectedGame setGridRating:rating];

    // TODO: can we only reload one item? Just redrawing might be faster
    [self reloadData];
}
#pragma mark - Renaming items
- (void)beginEditingWithSelectedItem:(id)sender
{
    if([[self selectionIndexes] count] != 1)
    {
        DLog(@"I can only rename a single game, sir.");
        return;
    }

    NSUInteger selectedIndex = [[self selectionIndexes] firstIndex];
    [self beginEditingItemAtIndex:selectedIndex];
}

- (void)beginEditingItemAtIndex:(NSInteger)index
{
    if(![[self fieldEditor] isHidden])
        [self OE_cancelFieldEditor];

    [self OE_setupFieldEditorForCellAtIndex:index];
}

#pragma mark -
- (void)OE_setupFieldEditorForCellAtIndex:(NSInteger)index
{
    IKImageBrowserCell *cell = [self cellForItemAtIndex:index];
    _editingIndex = index;

    NSRect fieldFrame = [cell titleFrame];
    fieldFrame        = NSOffsetRect(NSInsetRect(fieldFrame, 0.0, -1.0), 0.0, 1.0);
    [_fieldEditor setFrame:[self backingAlignedRect:fieldFrame options:NSAlignAllEdgesNearest]];

    NSString *title = [[cell representedItem] imageTitle];
    [_fieldEditor setString:title];
    [_fieldEditor setDelegate:self];
    [_fieldEditor setHidden:NO];
    [[self window] makeFirstResponder:[[_fieldEditor subviews] objectAtIndex:0]];
}

- (void)OE_cancelFieldEditor
{
    _editingIndex   = NSNotFound;

    if([_fieldEditor isHidden]) return;

    //OEGridCell *delegate = [_fieldEditor delegate];
    //if([delegate isKindOfClass:[OEGridViewCell class]]) [delegate setEditing:NO];

    [_fieldEditor setHidden:YES];
    [[self window] makeFirstResponder:self];
}

- (void)setDropIndex:(NSInteger)index dropOperation:(IKImageBrowserDropOperation)operation
{
    if(operation != IKImageBrowserDropOn || index == [[self dataSource] numberOfItemsInImageBrowser:self])
    {
        operation = IKImageBrowserDropBefore;
    }
    [super setDropIndex:index dropOperation:operation];
    _draggingOperation = operation;
}

#pragma mark - NSControlSubclassNotifications
- (void)controlTextDidEndEditing:(NSNotification *)obj
{
    // The _fieldEditor finished editing, so let's save the game with the new name
    if ([[[obj object] superview] isKindOfClass:[OEGridViewFieldEditor class]])
    {
        if(_editingIndex == NSNotFound) return;

        if([[self delegate] respondsToSelector:@selector(gridView:setTitle:forItemAtIndex:)])
        {
            NSString *title = [_fieldEditor string];
            [[self delegate] gridView:self setTitle:title forItemAtIndex:_editingIndex];
        }

        [self OE_cancelFieldEditor];
        [self reloadData];
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)fieldEditor doCommandBySelector:(SEL)commandSelector
{
    if ([[control superview] isKindOfClass:[OEGridViewFieldEditor class]])
    {
        // User pressed the 'Esc' key, cancel the editing
        if(commandSelector == @selector(cancelOperation:))
        {
            [self OE_cancelFieldEditor];
            return YES;
        }
    }
    
    return NO;
}
#pragma mark - IKImageBrowserView Private Overrides
- (BOOL)allowsTypeSelect
{
    return YES;
}

- (void)drawDragBackground
{}

- (void)drawDragOverlays
{
    id <IKRenderer> renderer = [self renderer];

    if([self dropOperation] != IKImageBrowserDropBefore) return;

    NSUInteger scaleFactor = [renderer scaleFactor];
    [renderer setColorRed:0.03 Green:0.41 Blue:0.85 Alpha:1.0];

    NSRect dragRect = [[self enclosingScrollView] documentVisibleRect];
    dragRect = NSInsetRect(dragRect, 1.0*scaleFactor, 1.0*scaleFactor);
    dragRect = NSIntegralRect(dragRect);

    [renderer drawRoundedRect:dragRect radius:8.0*scaleFactor lineWidth:2.0*scaleFactor cacheIt:YES];
}

- (void)drawBackground:(struct CGRect)arg1
{
    const id <IKRenderer> renderer = [self renderer];
    const CGFloat scaleFactor = [renderer scaleFactor];

    arg1 = [[self enclosingScrollView] documentVisibleRect];

    [renderer clearViewport:arg1];
    [renderer drawImage:lightingImage inRect:arg1 fromRect:NSZeroRect alpha:1.0];

    IKImageWrapper *image = noiseImageHighRes;
    if(scaleFactor != 1) image = noiseImageHighRes;

    NSSize imageSize = {image.size.width/scaleFactor, image.size.height/scaleFactor};
    for(CGFloat y=NSMinY(arg1); y < NSMaxY(arg1); y+=imageSize.height)
        for(CGFloat x=NSMinX(arg1); x < NSMaxX(arg1); x+=imageSize.width)
            [renderer drawImage:image inRect:(CGRect){{x,y},imageSize} fromRect:NSZeroRect alpha:1.0]
            ;
}

- (void)drawGroupsOverlays
{
    [super drawGroupsOverlays];

    const id <IKRenderer> renderer = [self renderer];
    const NSColor *fullColor  = [[NSColor blackColor] colorWithAlphaComponent:0.4];
    const NSColor *emptyColor = [NSColor clearColor];

    const NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    const NSRect gradientRectBottom = NSMakeRect(0.0, NSMinY(visibleRect), NSWidth(visibleRect), 8.0);
    const NSRect gradientRectTop = NSMakeRect(0.0, NSMaxY(visibleRect) - 8.0, NSWidth(visibleRect), 8.0);

    [renderer fillGradientInRect:gradientRectBottom bottomColor:fullColor topColor:emptyColor];
    [renderer fillGradientInRect:gradientRectTop bottomColor:emptyColor   topColor:fullColor];
    
    [renderer setColorRed:0.0 Green:0.0 Blue:0.0 Alpha:1.0];
    [renderer fillRect:NSMakeRect(0, NSMinY(visibleRect)-10, NSWidth(visibleRect), 10)];
}

#pragma mark - Groups
- (id)gridGroupFromDictionary:(NSDictionary*)arg1
{
    IKImageBrowserGridGroup *group = [super gridGroupFromDictionary:arg1];

    NSString *subtitle = [arg1 objectForKey:OEImageBrowserGroupSubtitleKey];
    if(subtitle) [group setObject:subtitle forKey:OEImageBrowserGroupSubtitleKey];

    return group;
}

- (void)drawGroupsBackground
{
    const NSRect visibleRect = [self visibleRect];
    [[[self layoutManager] groups] enumerateObjectsUsingBlock:^(IKImageBrowserGridGroup *group, NSUInteger idx, BOOL *stop) {
        const NSRect groupHeaderRect = [self _rectOfGroupHeader:group];
        // draw group header if it's visible
        if(!NSEqualRects(NSIntersectionRect(visibleRect, groupHeaderRect), NSZeroRect))
        {
            [self drawGroup:group withRect:groupHeaderRect];
        }
    }];

}

- (void)drawGroup:(IKImageBrowserGridGroup*)group withRect:(NSRect)headerRect
{
    const CGFloat HeaderLeftBorder  = 14.0;
    const CGFloat HeaderRightBorder = 14.0;

    id <IKRenderer> renderer = [self renderer];

    OEThemeState state = OEThemeStateDefault;

    NSImage *nsbackgroundImage = [[self groupBackgroundImage] imageForState:state];
    IKImageWrapper *backgroundImage = [IKImageWrapper imageWithNSImage:nsbackgroundImage];

    const NSSize backgroundImageSize = [backgroundImage size];
    headerRect.origin.y   += NSHeight(headerRect)-backgroundImageSize.height;
    headerRect.size.height = backgroundImageSize.height;

    [renderer drawImage:backgroundImage inRect:headerRect fromRect:NSZeroRect alpha:1.0];

    NSString *title = [group title];
    if(title != nil)
    {
        NSDictionary *titleAttributes = [[self groupTitleAttributes] textAttributesForState:state] ?: @{};
        NSRect titleRect = (NSRect){{NSMinX(headerRect)+HeaderLeftBorder, NSMinY(headerRect)},
            {NSWidth(headerRect)-HeaderLeftBorder, NSHeight(headerRect)}};

        // center text
        NSAttributedString *string = [[NSAttributedString alloc] initWithString:title attributes:titleAttributes];
        CGFloat stringHeight = [string size].height;
        titleRect = NSInsetRect(titleRect, 0, (NSHeight(titleRect)-stringHeight)/4.0);

        [renderer drawText:title inRect:titleRect withAttributes:titleAttributes withAlpha:1.0];
    }

    NSString *subtitle = [group objectForKey:OEImageBrowserGroupSubtitleKey];
    if(subtitle != nil)
    {
        NSDictionary *subtitleAttributes = [[self groupSubtitleAttributes] textAttributesForState:state] ?: @{};
        NSRect subtitleRect = (NSRect){{NSMinX(headerRect)+HeaderLeftBorder, NSMinY(headerRect)},
            {NSWidth(headerRect)-HeaderLeftBorder-HeaderRightBorder, NSHeight(headerRect)}};

        // center text
        NSAttributedString *string = [[NSAttributedString alloc] initWithString:subtitle attributes:subtitleAttributes];
        CGFloat stringHeight = [string size].height;
        subtitleRect = NSInsetRect(subtitleRect, 0, (NSHeight(subtitleRect)-stringHeight)/4.0);

        [renderer drawText:subtitle inRect:subtitleRect withAttributes:subtitleAttributes withAlpha:1.0];
    }
}

#pragma mark -
- (void)private_setClipsToBounds:(BOOL)flag
{
    if([self respondsToSelector:@selector(setClipsToBounds:)])
        [self setClipsToBounds:flag];
}
@end
