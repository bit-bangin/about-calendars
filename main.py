''' Module '''
from datetime import datetime

class IntervalNode:
    '''Represents a single node in the interval tree'''
    def __init__(self, start, end):
        self.interval = (start, end)  # The interval stored at this node
        self.max_end = end  # The maximum end time in the subtree rooted at this node
        self.left = None  # Pointer to the left child
        self.right = None  # Pointer to the right child

# The interval tree itself
class IntervalTree:
    '''Class representing the interval tree'''
    def __init__(self):
        self.root = None  # The root of the tree

    # Public method to insert a new interval
    def insert(self, start, end):
        '''Public method to insert a new interval.'''
        self.root = self._insert(self.root, start, end)

    # Private recursive method to insert an interval into the tree
    def _insert(self, node, start, end):
        if not node:  # If the current node is empty, create a new one
            return IntervalNode(start, end)

        if start < node.interval[0]:  # If the interval starts earlier, go to the left subtree
            node.left = self._insert(node.left, start, end)
        else:  # Otherwise, go to the right subtree
            node.right = self._insert(node.right, start, end)

        # Update the max_end for the current node
        node.max_end = max(node.max_end, end)
        return node

    def query(self, start, end):
        '''Public method to query intervals that overlap with a given range'''
        return self._query(self.root, start, end)

    def _query(self, node, start, end):
        '''Private recursive method to query overlapping intervals'''
        if not node:  # Base case: if the current node is empty, return an empty list
            return []

        results = []

        # Check if the current node's interval overlaps with the query range
        if node.interval[0] <= end and start <= node.interval[1]:
            results.append(node.interval)

        # If the max_end of the left subtree is >= start, there might be overlaps on the left
        if node.left and node.left.max_end >= start:
            results.extend(self._query(node.left, start, end))

        # Always check the right subtree for potential overlaps
        results.extend(self._query(node.right, start, end))
        return results

def subtract_intervals(available, busy):
    '''Helper function to subtract busy intervals from available intervals'''
    result = []
    for avail_start, avail_end in available:
        current_start = avail_start  # Initialize the current start time
        for busy_start, busy_end in busy:
            # If current_start is during a busy interval
            if busy_start <= current_start < busy_end:
                # Move current_start past the busy interval
                current_start = max(current_start, busy_end)
                # If a busy interval is in the middle
            elif current_start < busy_start < avail_end:
                # Add the free time before the busy interval
                result.append((current_start, busy_start))
                # Move current_start past the busy interval
                current_start = max(current_start, busy_end)

        # Add any remaining free time after all busy intervals
        if current_start < avail_end:
            result.append((current_start, avail_end))
    return result

# Step 1: Input data for interviewers
interviewer_1_days = [(datetime(2024, 11, 20, 9, 0), datetime(2024, 11, 20, 17, 0))]
interviewer_1_busy = [(datetime(2024, 11, 20, 9, 30), datetime(2024, 11, 20, 10, 30))]

interviewer_2_days = [(datetime(2024, 11, 20, 10, 0), datetime(2024, 11, 20, 18, 0))]
interviewer_2_busy = [(datetime(2024, 11, 20, 12, 0), datetime(2024, 11, 20, 13, 0))]

interviewer_3_days = [(datetime(2024, 11, 21, 9, 0), datetime(2024, 11, 21, 17, 0))]
interviewer_3_busy = [(datetime(2024, 11, 21, 11, 0), datetime(2024, 11, 21, 12, 0))]

# Step 2: Build a day-level interval tree with all interviewers' availability
day_tree = IntervalTree()
for day in interviewer_1_days + interviewer_2_days + interviewer_3_days:
    day_tree.insert(day[0], day[1])

# Query the tree for overlapping availability on a specific day
query_day_start = datetime(2024, 11, 20, 0, 0)
query_day_end = datetime(2024, 11, 20, 23, 59)
overlapping_days = day_tree.query(query_day_start, query_day_end)

print("Overlapping days:", overlapping_days)

# Step 3: Refine time slots for each interviewer by subtracting busy intervals
interviewer_1_free = subtract_intervals(interviewer_1_days, interviewer_1_busy)
interviewer_2_free = subtract_intervals(interviewer_2_days, interviewer_2_busy)

print("Interviewer 1 refined slots:", interviewer_1_free)
print("Interviewer 2 refined slots:", interviewer_2_free)

# Step 4: Build a time-level interval tree for one interviewer and find overlaps
time_tree = IntervalTree()
for interval in interviewer_1_free:
    time_tree.insert(interval[0], interval[1])

# Find overlapping free time slots between two interviewers
final_overlaps = []
for interval in interviewer_2_free:
    final_overlaps.extend(time_tree.query(interval[0], interval[1]))

print("Final overlapping time slots:", final_overlaps)
