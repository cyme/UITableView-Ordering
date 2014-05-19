//
//  UITableView+Ordering.m
//
//  Copyright (c) 2013 Cyril Meurillon. All rights reserved.
//

// This is a quick and dirty implementation, and it hasn't been stress-tested. The code is dense and not particularly
// readable either.
//
// Deleted and reloaded rows and sections are stored respectively in the orderingDeletedIndexPaths and orderingReloadedIndexPaths arrays
// of NSIndexPath objects. The NSIndexPath objects represent the section and row of the row operated on. In the case of whole
// sections, the row property of the NSIndexPath objects holds the value -1. The NSIndexPath objects are kept sorted in
// descending order, as this is the order they have to be "played back"
//
// Inserted rows and sections are stored in the orderingInsertedIndexPaths array of NSIndexPath objects. As with deleted and reloaded
// sections, whole sections inserted are represented by NSIndexPath objects with the row property holding the value -1. But
// unlike their delete and reload counterpart, inserted rows and sections are stored in ascending order and using relative
// values for code optimization reasons. For example, the sequence of inserted rows (0,0), (0,3), (0,7), (1,3), (4,2) and
// inserted sections 3 and 6 would be represented as the following sequence: (0,0), (0,3), (0,4), (1,3), (2,-1), (1,2), (2,-1)
//
// the arrays {deleted,reloaded,inserted}IndexathAnimations hold the animation type requested for the rows/section operations
// at the corresponding indexes.




#import "UITableView+Ordering.h"
#import <objc/runtime.h>



@interface UITableView (OrderingPrivate)

@property NSInteger                     orderingUpdateNestingLevel;

@property (nonatomic) NSMutableArray    *orderingDeletedIndexPaths;
@property (nonatomic) NSMutableArray    *orderingInsertedIndexPaths;
@property (nonatomic) NSMutableArray    *orderingReloadedIndexPaths;

@property (nonatomic) NSMutableArray    *orderingDeletedIndexPathAnimations;
@property (nonatomic) NSMutableArray    *orderingInsertedIndexPathAnimations;
@property (nonatomic) NSMutableArray    *orderingReloadedIndexPathAnimations;

@end



@implementation UITableView (Ordering)

#pragma mark - Public interface implementation

// initiate an update session

- (void)beginOrderedUpdates {
    
    // update sessions can be nested. Initialize the support structures when the outer session is initiated
    
    self.orderingUpdateNestingLevel++;
    if (self.orderingUpdateNestingLevel == 1) {
        self.orderingDeletedIndexPaths = [NSMutableArray array];
        self.orderingInsertedIndexPaths = [NSMutableArray array];
        self.orderingReloadedIndexPaths = [NSMutableArray array];
        self.orderingDeletedIndexPathAnimations = [NSMutableArray array];
        self.orderingInsertedIndexPathAnimations = [NSMutableArray array];
        self.orderingReloadedIndexPathAnimations = [NSMutableArray array];
    }
}


// close an update session

- (void)endOrderedUpdates {
    
    // update sessions can be nested. "Play back" the UITableView operations when the outer session is closed.
    
    self.orderingUpdateNestingLevel--;
    
    if (self.orderingUpdateNestingLevel == 0) {
        
        if ([self hasOperationsToPlayback]) {
            
            [self beginUpdates];

            [self playbackorderingReloadedIndexPaths];
            [self playbackorderingDeletedIndexPaths];
            [self playbackorderingInsertedIndexPaths];
            
            [self endUpdates];
        }
        
        self.orderingDeletedIndexPaths = nil;
        self.orderingInsertedIndexPaths = nil;
        self.orderingReloadedIndexPaths = nil;
        self.orderingDeletedIndexPathAnimations = nil;
        self.orderingInsertedIndexPathAnimations = nil;
        self.orderingReloadedIndexPathAnimations = nil;
    }
}


// insert a series of whole sections in the SLArrayTableView

- (void)insertOrderedSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation {
    
    [sections enumerateIndexesUsingBlock: ^(NSUInteger index, BOOL *stop) {
        [self insertIndexPath:[NSIndexPath indexPathForRow:-1 inSection:index] withRowAnimation:animation];
    }];
}


// delete a series of whole sections in the SLArrayTableView

- (void)deleteOrderedSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation {
    
    [sections enumerateIndexesUsingBlock: ^(NSUInteger index, BOOL *stop) {
        [self deleteIndexPath:[NSIndexPath indexPathForRow:-1 inSection:index] withRowAnimation:animation];
    }];
}


// reload a series of whole sections in the SLArrayTableView

- (void)reloadOrderedSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation {
    
    [sections enumerateIndexesUsingBlock: ^(NSUInteger index, BOOL *stop) {
        [self reloadIndexPath:[NSIndexPath indexPathForRow:-1 inSection:index] withRowAnimation:animation];
    }];
    
}


// insert a series of rows in the SLArrayTableView

- (void)insertOrderedRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation: (UITableViewRowAnimation)animation {
    
    for(NSIndexPath *indexPath in indexPaths)
        [self insertIndexPath:indexPath withRowAnimation:animation];
}


// delete a series of rows in the SLArrayTableView

- (void)deleteOrderedRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation: (UITableViewRowAnimation)animation {
    
    for(NSIndexPath *indexPath in indexPaths)
        [self deleteIndexPath:indexPath withRowAnimation:animation];
}


// reload a series of rows in the SLArrayTableView

- (void)reloadOrderedRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation {
    
    for(NSIndexPath *indexPath in indexPaths)
        [self reloadIndexPath:indexPath withRowAnimation:animation];
}


#pragma mark - Private implementation

// insert a single row/section

- (void) insertIndexPath:(NSIndexPath *)indexPath withRowAnimation:(UITableViewRowAnimation)animation {
    NSInteger               i, count, section, row, curRow, curSection;
    NSIndexPath             *curIndexPath;

    i = 0;
    count = [self.orderingInsertedIndexPaths count];
    section = indexPath.section;
    row = indexPath.row;
    
    // find the slot where to insert the row/section by iterating over the already inserted rows/sections
    
    while (i<count) {
        curIndexPath = (NSIndexPath *)self.orderingInsertedIndexPaths[i];
        curRow = curIndexPath.row;
        curSection = curIndexPath.section;
        
        // case of inserting a row in a newly inserted section:
        // no need to log the row insertion, as the whole section will be loaded
        
        if ((curSection == section) && (row >= 0) && (curRow < 0))
            return;
        
        // case of inserting a section before another newly inserted section/row
        // we need to increment the section count of the newly inserted section/row ahead
        
        if ((curSection >= section) && (row < 0)) {
            self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curRow inSection:curSection-section+1];
            break;
        }
   
        // case of inserting a row in a section before another newly inserted section/row
        // we need to ajust the section count of the newly inserted section/row ahead
        
        if ((curSection > section) && (row >= 0)) {
            self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curRow inSection:curSection-section];
            break;
        }

        // case of inserting a row before another newly inserted row in the same section
        // we need to increment the row count of the newly inserted section ahead
        
        if ((curSection == section) && (curRow >= row)) {
            self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curRow-row+1 inSection:0];
            break;
        }
        section -= curSection;
        if ((section == 0) && (row >= 0))
            row -= curRow;
        i++;
    }
    
    // we found the slot. Insert the row/section at this position.
    
    [self.orderingInsertedIndexPaths insertObject:[NSIndexPath indexPathForRow:row inSection:section] atIndex:i];
    [self.orderingInsertedIndexPathAnimations insertObject:[NSNumber numberWithUnsignedInteger:animation] atIndex:i];
}


// delete a single row/section

- (void) deleteIndexPath:(NSIndexPath *)indexPath withRowAnimation:(UITableViewRowAnimation)animation{
    NSInteger               i, count;
    NSInteger               section, row;
    NSInteger               leftSection, leftRow;
    NSInteger               curSection, curRow, lastSection;
    NSInteger               addedSections, addedRows;
    BOOL                    deletingSection;
    NSIndexPath             *curIndexPath;
    
    deletingSection = (indexPath.row < 0);
    section = indexPath.section;
    row = indexPath.row;
    
    i = 0;
    count = [self.orderingInsertedIndexPaths count];
    addedSections = 0;
    addedRows = 0;
    leftSection = indexPath.section;
    leftRow = indexPath.row;
    
    // first check if the deletion collides with a newly inserted row or section
    
    while (i<count) {
        curIndexPath = (NSIndexPath *)self.orderingInsertedIndexPaths[i];
        curRow = curIndexPath.row;
        curSection = curIndexPath.section;
        
        // case of the deletion of a section that was not newly inserted. we need to updated the section index of the next added section/row
        
        if ((curSection > leftSection) && deletingSection) {
            self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curRow inSection:curSection-1];
            break;
        }
        
        // case of the deletion of a section that contains newly inserted rows.
        // we  need to drop the newly inserted rows
        
        if ((curSection == leftSection) && deletingSection && (curRow >= 0)) {
            do {
                [self.orderingInsertedIndexPaths removeObjectAtIndex:i];
                [self.orderingInsertedIndexPathAnimations removeObjectAtIndex:i];
                count--;
            } while ((i<count) && (((NSIndexPath *)self.orderingInsertedIndexPaths[i]).section == 0));
            if (i<count) {
                curIndexPath = self.orderingInsertedIndexPaths[i];
                if (curIndexPath.section == 0)
                    self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curIndexPath.row+curRow-1 inSection:0];
                else {
                    if ((i == 0) || (curSection > 0))
                        self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curIndexPath.row inSection:curIndexPath.section+curSection];
                }
            }
            break;
        }
        
        // case of the deletion of a section that was newly inserted
        // we  just need to drop the newly inserted section and we're done.
        
        if ((curSection == leftSection) && deletingSection && (curRow < 0)) {
            [self.orderingInsertedIndexPaths removeObjectAtIndex:i];
            [self.orderingInsertedIndexPathAnimations removeObjectAtIndex:i];
            count--;
            if (i<count) {
                curIndexPath = self.orderingInsertedIndexPaths[i];
                self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curIndexPath.row inSection:curIndexPath.section+curSection-1];
            }
            return;
        }
        
        // case of a row deletion in a section was that was not newly inserted. we don't need to update any index.
        
        if ((curSection > leftSection) && !deletingSection)
            break;
        
        // case of a row deletion in a newly inserted section. the deletion does not need to be logged as the whole section will be loaded
        
        if ((curSection == leftSection) && !deletingSection && (curRow < 0))
            return;
        
        // case of the deletion of a row that was newly inserted. we just need to drop the insertion
        
        if ((curSection == leftSection) && !deletingSection && (curRow == leftRow)) {
            [self.orderingInsertedIndexPaths removeObjectAtIndex:i];
            [self.orderingInsertedIndexPathAnimations removeObjectAtIndex:i];
            count--;
            if (i<count) {
                curIndexPath = self.orderingInsertedIndexPaths[i];
                if (curIndexPath.section == 0)
                    self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curIndexPath.row+curRow-1 inSection:0];
                else {
                    if ((i == 0) || (curSection > 0))
                        self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curIndexPath.row inSection:curIndexPath.section+curSection];
                }
            }
            return;
        }
        
        // case of the deletion of a row appearing before a newly inserted row. we need to update the inserted row index
        
        if ((curSection == leftSection) && !deletingSection && (curRow > leftRow)) {
            self.orderingInsertedIndexPaths[i] = [NSIndexPath indexPathForRow:curRow-1 inSection:curSection];
            break;
        }
        
        leftSection -= curSection;
        if ((leftSection > 0) && (curRow < 0))
            addedSections++;
        if (!deletingSection && (leftSection == 0) && (leftRow > 0)) {
            leftRow -= curRow;
            addedRows++;
        }
        i++;
    }
    
    // deduct the number of sections and rows inserted before the deleted row/section.
    // this is necessary because deletions refer to the original table order
    
    section -= addedSections;
    if (!deletingSection)
        row -= addedRows;
    
    // calculate the number of sections and row deleted before this one.
    // this is necessary because deletions refer to the original table order
    
    i=0;
    lastSection = -1;
    count = [self.orderingDeletedIndexPaths count];
    while (i<count) {
        indexPath = self.orderingDeletedIndexPaths[count-1-i];
        curSection = indexPath.section;
        curRow = indexPath.row;
        
        // the next deleted section/row is in a section ahead of the deleted section/row. we can stop counting
        
        if (curSection > section)
            break;
        
        // we have found the next deleted row ahead of the deleted row, we can stop counting
        
        if ((curSection == section) && !deletingSection && (curRow > row))
            break;
        
        // case of deleting a section that contains deleted rows. we need to drop the deleted sections.
        
        if ((curSection == section) && deletingSection && (curRow >= 0)) {
            do {
                [self.orderingDeletedIndexPaths removeObjectAtIndex:count-1-i];
                [self.orderingDeletedIndexPathAnimations removeObjectAtIndex:count-1-i];
                count--;
            } while ((i<count) && (((NSIndexPath *)self.orderingDeletedIndexPaths[count-1-i]).section == curSection));
            break;
        }
        
        if ((curSection != lastSection) && (curRow < 0))
            section++;
        if (!deletingSection && (curSection == section))
            row++;
        i++;
        lastSection = curSection;
    }
    
    // check if the deletion collides with any reloaded section or row
    
    i=0;
    count = [self.orderingReloadedIndexPaths count];
    while (i<count) {
        indexPath = self.orderingReloadedIndexPaths[i];
        curSection = indexPath.section;
        curRow = indexPath.row;
        if (curSection > section)
            break;
        if (!deletingSection && (curSection == section) && (curRow > row))
            break;
        
        // if the deleted row/section coincides with a reloaded row/section, drop the reload
        
        if ((curSection == section) && (deletingSection || (curRow == row))) {
            [self.orderingReloadedIndexPaths removeObjectAtIndex:i];
            [self.orderingReloadedIndexPathAnimations removeObjectAtIndex:i];
            count--;
            i--;
        }
        i++;
    }
    
    // log the deletion operation
    
    i=0;
    count = [self.orderingDeletedIndexPaths count];
    while (i<count) {
        indexPath = self.orderingDeletedIndexPaths[i];
        curSection = indexPath.section;
        curRow = indexPath.row;
        assert(!(deletingSection && (curSection == section)));
        assert(!(!deletingSection && (curSection == section) && (curRow == row)));
        if (curSection < section)
            break;
        if (!deletingSection && (curSection == section) && (curRow < row))
            break;
        i++;
    }
    [self.orderingDeletedIndexPaths insertObject:[NSIndexPath indexPathForRow:row inSection:section] atIndex:i];
    [self.orderingDeletedIndexPathAnimations insertObject:[NSNumber numberWithUnsignedInteger:animation] atIndex:i];
}


// reload a single row/section

- (void) reloadIndexPath:(NSIndexPath *)indexPath withRowAnimation:(UITableViewRowAnimation)animation {
    NSInteger               i, count;
    NSInteger               section, row;
    NSInteger               leftSection, leftRow;
    NSInteger               curSection, curRow, lastSection;
    NSInteger               addedSections, addedRows;
    NSInteger               deletedSections, deletedRows;
    BOOL                    reloadingSection;
    NSIndexPath             *curIndexPath;

    section = indexPath.section;
    row = indexPath.row;
    reloadingSection = (row < 0);
    
    i = 0;
    count = [self.orderingInsertedIndexPaths count];
    addedSections = 0;
    addedRows = 0;
    leftSection = indexPath.section;
    leftRow = indexPath.row;
    
    // calculate the number of sections/rows inserted ahead of the reloaded section/row
    // while we do this, we'll see if the reloaded section/row collides with a newly inserted section/row
    
    while (i<count) {
        curIndexPath = (NSIndexPath *)self.orderingInsertedIndexPaths[i];
        curRow = curIndexPath.row;
        curSection = curIndexPath.section;
        
        // the reloaded row/section is in a section before another newly inserted row/section
        // we can stop counting the number of sections and rows ahead
        
        if (curSection > leftSection)
            break;
        
        // the reloaded row is in a section before another newly inserted row
        // we can stop counting the number of sections and rows ahead
        
        if ((curSection == leftSection) && !reloadingSection && (curRow > leftRow))
            break;
        
        // case of a section/row reload of a newly inserted section. we don't need to log the reload
        // operation as the whole section will be loaded
        
        if ((curSection == leftSection) && (curRow < 0))
            return;
        
        // case of the row reload of a newly inserted row. we don't need to log the reload operation
        // as the row will be loaded
        
        if ((curSection == leftSection) && !reloadingSection && (curRow == leftRow))
            return;
        
        leftSection -= curSection;
        if (((i == 0) || (curSection > 0)) && (curRow < 0))
            addedSections++;
        if (!reloadingSection && (leftSection == 0) && (leftRow >= 0)) {
            leftRow -= curRow;
            addedRows++;
        }
        i++;
    }
    
    // deduct the number of sections and rows added before the reloaded row/section.
    // this is necessary because reloads refer to the original table order.
    
    section -= addedSections;
    if (!reloadingSection)
        row -= addedRows;
    
    // calculate the number of sections and row deleted before the reloaded section/row.
    // this is necessary because reloads refer to the original table order.
    
    deletedSections = 0;
    deletedRows = 0;
    i=0;
    lastSection = -1;
    count = [self.orderingDeletedIndexPaths count];
    while (i<count) {
        indexPath = self.orderingDeletedIndexPaths[count-1-i];
        curSection = indexPath.section;
        curRow = indexPath.row;
        
        // the next deleted section/row is in a section ahead of the reloaded section/row. we can stop counting
        
        if (curSection > section)
            break;
        
        // we have found deleted rows in the reloaded section. we can stop counting
        
        if ((curSection == section) && (curRow >= 0) && reloadingSection)
            break;
        
        // we have found the next deleted row ahead of the reloaded row. we can stop counting
        
        if ((curSection == section) && (curRow >= 0) && (curRow > row))
            break;
        
        if ((curSection != lastSection) && (curRow < 0))
            deletedSections++;
        if (!reloadingSection && (curSection == section))
            deletedRows++;
        i++;
        lastSection = curSection;
    }
    
    section += deletedSections;
    if (!reloadingSection)
        row += deletedRows;
    
    // now finds the slot where to insert the reloaded row/section
    
    i=0;
    count = [self.orderingReloadedIndexPaths count];
    while (i<count) {
        indexPath = self.orderingReloadedIndexPaths[i];
        curSection = indexPath.section;
        curRow = indexPath.row;
        
        // case of reloading a section that contains a reloaded row. We can drop the reloaded row.
        
        if (reloadingSection && (curSection == section) && (curRow >= 0)) {
            [self.orderingReloadedIndexPaths removeObjectAtIndex:i];
            [self.orderingReloadedIndexPathAnimations removeObjectAtIndex:i];
            count--;
            i--;
        }
        
        // case of reloading a section that is already being reloaded. we can drop this reload operation.
        
        if (reloadingSection && (curSection == section) && (curRow < 0))
            return;
        
        // case of reloading a row in a section that is already being reloaded. we can drop this reload operation
        
        if (!reloadingSection && (curSection == section) && (curRow < 0))
            return;
        
        // case of reloading a row that is already being reloaded. we can drop this reload operation
        
        if (!reloadingSection && (curSection == section) && (curRow == row))
            return;
        
        if (curSection < section)
            break;
        if (!reloadingSection && (curSection == section) && (curRow < row))
            break;
        
        i++;
    }
    
    // we found the slot, now insert the reload operation
    
    [self.orderingReloadedIndexPaths insertObject:[NSIndexPath indexPathForRow:row inSection:section] atIndex:i];
    [self.orderingReloadedIndexPathAnimations insertObject:[NSNumber numberWithUnsignedInteger:animation] atIndex:i];
}


// Play back row/section deletions at the end of an update session

- (void) playbackorderingDeletedIndexPaths {
    NSInteger                   i, count, section, row;
    NSIndexPath                 *indexPath;
    UITableViewRowAnimation     animation;

    // the orderingDeletedIndexPaths array holds all deletion operations in the correct order.
    
    i=0;
    count = [self.orderingDeletedIndexPaths count];
    while (i<count) {
        indexPath = (NSIndexPath *)(self.orderingDeletedIndexPaths[i]);
        section = indexPath.section;
        row = indexPath.row;
        animation = [self.orderingDeletedIndexPathAnimations[i] unsignedIntegerValue];
        if (row < 0)
            [self deleteSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:animation];
        else
            [self deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:section]] withRowAnimation:animation];
        i++;
    }
}

- (BOOL) hasOperationsToPlayback {
    
    if ([self.orderingInsertedIndexPaths count] > 0)
        return TRUE;
    if ([self.orderingReloadedIndexPaths count] > 0)
        return TRUE;
    if ([self.orderingDeletedIndexPaths count] > 0)
        return TRUE;
    return FALSE;
}

// Play back row/section reloads at the end of an update session

- (void) playbackorderingReloadedIndexPaths {
    NSInteger                   i, count, section, row;
    NSIndexPath                 *indexPath;
    UITableViewRowAnimation     animation;
    
    // the reloadIndexPaths array holds all reload operations in the correct order.

    i=0;
    count = [self.orderingReloadedIndexPaths count];
    while (i<count) {
        indexPath = (NSIndexPath *)(self.orderingReloadedIndexPaths[i]);
        section = indexPath.section;
        row = indexPath.row;
        animation = [self.orderingReloadedIndexPathAnimations[i] unsignedIntegerValue];
        if (row < 0)
            [self reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:animation];
        else
            [self reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:section]] withRowAnimation:animation];
        i++;
    }
}


// Play back row/section insertions at the end of an update session

- (void) playbackorderingInsertedIndexPaths {
    NSInteger                   i, count, section, row;
    NSIndexPath                 *indexPath;
    UITableViewRowAnimation     animation;

    // the orderingInsertedIndexPaths array holds all insertion operations in the correct order.
    // We just need to generate absolute NSIndexPath from relative indexes.

    i=0;
    count = [self.orderingInsertedIndexPaths count];
    section = 0;
    row = 0;
    while (i<count) {
        indexPath = (NSIndexPath *)(self.orderingInsertedIndexPaths[i]);
        section += indexPath.section;
        if (indexPath.row < 0)
            row = -1;
        else
            if (indexPath.section == 0)
                row += indexPath.row;
            else
                row = indexPath.row;
        animation = [self.orderingInsertedIndexPathAnimations[i] unsignedIntegerValue];
        
        if (row < 0)
            [self insertSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:animation];
        else
            [self insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:section]] withRowAnimation:animation];
        i++;
    }
}

@end


@implementation UITableView (OrderingPrivate)

static char orderingUpdateNestingLevelKey;

- (NSInteger)orderingUpdateNestingLevel {
    
    NSNumber        *value;
    
    value = objc_getAssociatedObject(self, &orderingUpdateNestingLevelKey);
    if (value)
        return [value intValue];
    return 0;
}

- (void)setOrderingUpdateNestingLevel:(NSInteger)orderingUpdateNestingLevel {
    objc_setAssociatedObject(self, &orderingUpdateNestingLevelKey, @(orderingUpdateNestingLevel), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static char orderingDeletedIndexPathsKey;

- (NSMutableArray *)orderingDeletedIndexPaths {
    return objc_getAssociatedObject(self, &orderingDeletedIndexPathsKey);
}

- (void)setOrderingDeletedIndexPaths:(NSMutableArray *)orderingDeletedIndexPaths {
    objc_setAssociatedObject(self, &orderingDeletedIndexPathsKey, orderingDeletedIndexPaths, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static char orderingInsertedIndexPathsKey;

- (NSMutableArray *)orderingInsertedIndexPaths {
    return objc_getAssociatedObject(self, &orderingInsertedIndexPathsKey);
}

- (void)setOrderingInsertedIndexPaths:(NSMutableArray *)orderingInsertedIndexPaths {
    objc_setAssociatedObject(self, &orderingInsertedIndexPathsKey, orderingInsertedIndexPaths, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static char orderingReloadedIndexPathsKey;

- (NSMutableArray *)orderingReloadedIndexPaths {
    return objc_getAssociatedObject(self, &orderingReloadedIndexPathsKey);
}

- (void)setOrderingReloadedIndexPaths:(NSMutableArray *)orderingReloadedIndexPaths {
    objc_setAssociatedObject(self, &orderingReloadedIndexPathsKey, orderingReloadedIndexPaths, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static char orderingDeletedIndexPathAnimationsKey;

- (NSMutableArray *)orderingDeletedIndexPathAnimations {
    return objc_getAssociatedObject(self, &orderingDeletedIndexPathAnimationsKey);
}

- (void)setOrderingDeletedIndexPathAnimations:(NSMutableArray *)orderingDeletedIndexPathAnimations {
    objc_setAssociatedObject(self, &orderingDeletedIndexPathAnimationsKey, orderingDeletedIndexPathAnimations, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static char orderingInsertedIndexPathAnimationsKey;

- (NSMutableArray *)orderingInsertedIndexPathAnimations {
    return objc_getAssociatedObject(self, &orderingInsertedIndexPathAnimationsKey);
}

- (void)setOrderingInsertedIndexPathAnimations:(NSMutableArray *)orderingInsertedIndexPathAnimations {
    objc_setAssociatedObject(self, &orderingInsertedIndexPathAnimationsKey, orderingInsertedIndexPathAnimations, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static char orderingReloadedIndexPathAnimationsKey;

- (NSMutableArray *)orderingReloadedIndexPathAnimations {
    return objc_getAssociatedObject(self, &orderingReloadedIndexPathAnimationsKey);
}

- (void)setOrderingReloadedIndexPathAnimations:(NSMutableArray *)orderingReloadedIndexPathAnimations {
    objc_setAssociatedObject(self, &orderingReloadedIndexPathAnimationsKey, orderingReloadedIndexPathAnimations, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end