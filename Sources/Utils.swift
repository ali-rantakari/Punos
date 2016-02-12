//
//  Utils.swift
//  Punos
//
//  Created by Ali Rantakari on 10/02/2016.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation

func dispatchAfterInterval(interval: NSTimeInterval, queue: dispatch_queue_t, block: () -> Void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(interval * Double(NSEC_PER_SEC))), queue, block);
}
