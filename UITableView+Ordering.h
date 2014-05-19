//
//  UIArrayTableView+Ordering.h
//
//  Copyright (c) 2013 Cyril Meurillon. All rights reserved.
//


// This UITableView category addresses the following problem:
// the UITableView batch edition methods {insert/delete/reload}{RowsAtIndexPaths/Sections}: take row/section indexes that refer
// to the initial table order (delete & reload methods) and to the post-delete order (insert methods). This makes it
// difficult to use NSMutableArray for the data source of a dynamic UITableView, particularly when edition operations may happen
// in a random sequence. This is the case when the table view displays data backed by SyncLib, as the data source needs to respond
// to the asynchronous update notifications of the SLObservingObject protocol. In this case a table update session may consist
// of several row insertions and deletions in an unknown order. This sequence has to be properly re-ordered and indexes recalculated
// to comply with the UITableView edition methods ordering convention.
//
// The category offers alternate batch edition methods that follows the ordering scheme of NSMutableArray, with
// indexes shifting as rows and sections are inserted or deleted. The alternate batch edition methods use the same syntax as
// their original counterpart, and they can be called in any order without restriction. At the end of the update session,
// the method - endOrderedUpdates: plays back the sequence of operations, after it has optimized it and ordered it properly.
// This makes the translation of update notifications to UITableView operations straightforward, as the indexes of the elements
// as found in the NSMutableArray can be used as is.
//
// This is a quick and dirty implementation, and it hasn't been extensively tested.


#import <UIKit/UIKit.h>

@interface UITableView(Ordering)

#pragma mark - Table batch edition methods

// all methods below match the syntax of their UITableView counterparts

- (void)beginOrderedUpdates;
- (void)endOrderedUpdates;

- (void)insertOrderedSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation;
- (void)deleteOrderedSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation;
- (void)reloadOrderedSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation;

- (void)insertOrderedRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation: (UITableViewRowAnimation)animation;
- (void)deleteOrderedRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation: (UITableViewRowAnimation)animation;
- (void)reloadOrderedRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation;


@end
